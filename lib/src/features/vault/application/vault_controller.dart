import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/crypto/key_derivation_service.dart';
import '../../../core/crypto/payload_cipher_service.dart';
import '../../../core/crypto/signing_service.dart';
import '../../../core/db/local_note_vault.dart';
import '../../../core/errors/vault_exceptions.dart';
import '../../../core/storage/secure_credentials_store.dart';
import '../../auth/application/auth_controller.dart';
import '../data/profile_repository.dart';
import 'vault_state.dart';

final vaultControllerProvider = NotifierProvider<VaultController, VaultState>(
  VaultController.new,
);

class VaultController extends Notifier<VaultState> {
  static const _keyDerivation = KeyDerivationService();
  static final _signing = SigningService();
  static final _cipher = PayloadCipherService();
  final _credentials = SecureCredentialsStore();
  final _profiles = ProfileRepository();

  @override
  VaultState build() => const VaultLocked();

  Future<void> unlock(String passphrase) async {
    if (passphrase.isEmpty) {
      state = const VaultError('Vault passphrase cannot be empty.');
      return;
    }

    final userId = ref.read(currentUserProvider)?.id;
    if (userId == null) {
      state = const VaultError('You must be signed in before unlocking the vault.');
      return;
    }

    state = const VaultUnlocking();
    try {
      // The salt isn't secret, so it's safe to persist as soon as it
      // exists. Prefer the local cache (works offline); a new device with
      // no local cache falls back to the salt already escrowed in this
      // user's profile, so it derives the same key the first device did.
      var salt = await _credentials.readSalt(userId);
      VaultProfile? remoteProfile;
      if (salt == null) {
        remoteProfile = await _profiles.fetch(userId);
        salt = remoteProfile?.salt;
      }
      final isFirstEverSetup = salt == null;
      salt ??= _keyDerivation.generateSalt();
      await _credentials.writeSalt(userId, salt);

      // `profiles.salt` is NOT NULL, so on first-ever setup this must land
      // before `_ensureSigningKeyMaterial` — that method upserts
      // `public_key`/`encrypted_private_key` and, when there's no row yet,
      // that upsert is an INSERT that would violate the constraint if salt
      // hadn't been written first.
      if (isFirstEverSetup) {
        await _profiles.upsertSalt(userId, salt);
      }

      final payloadKeyBytes = await _keyDerivation.derive(passphrase: passphrase, salt: salt);

      // Tier 1 (whole-file encryption) fails closed on a wrong passphrase
      // via LocalNoteVault's own integrity check, so by the time this
      // resolves we know `passphrase` was correct.
      final vault = await LocalNoteVault.open(passphrase: passphrase);

      final signingKeyMaterial = await _ensureSigningKeyMaterial(
        userId: userId,
        salt: salt,
        payloadKeyBytes: payloadKeyBytes,
        remoteProfile: remoteProfile,
      );

      final deviceId = await _credentials.ensureDeviceId();

      state = VaultUnlocked(
        vault: vault,
        payloadKeyBytes: payloadKeyBytes,
        signingKeyMaterial: signingKeyMaterial,
        deviceId: deviceId,
      );
    } on VaultInitializationException catch (error) {
      state = VaultError(error.message);
    } catch (error) {
      state = VaultError('Failed to unlock vault: $error');
    }
  }

  /// Ed25519 identity is per-*user*, not per-device: generated once and
  /// escrowed (private key encrypted with the Tier-2 key) in `profiles` so
  /// every device the user signs into recovers the same identity — matching
  /// the convention already established by this Supabase project's sibling
  /// apps, rather than the per-device model originally sketched for this
  /// app alone.
  Future<Ed25519KeyMaterial> _ensureSigningKeyMaterial({
    required String userId,
    required Uint8List salt,
    required Uint8List payloadKeyBytes,
    VaultProfile? remoteProfile,
  }) async {
    final cachedPrivateKey = await _credentials.readEd25519PrivateKey(userId);
    final cachedPublicKey = await _credentials.readEd25519PublicKey(userId);
    if (cachedPrivateKey != null && cachedPublicKey != null) {
      return Ed25519KeyMaterial(privateKeyBytes: cachedPrivateKey, publicKeyBytes: cachedPublicKey);
    }

    remoteProfile ??= await _profiles.fetch(userId);
    final remotePublicKey = remoteProfile?.publicKey;
    final remoteEncryptedPrivateKey = remoteProfile?.encryptedPrivateKey;

    if (remotePublicKey != null && remoteEncryptedPrivateKey != null) {
      final privateKeyBytes = await _cipher.decryptBytes(remoteEncryptedPrivateKey, payloadKeyBytes);
      final recovered = Ed25519KeyMaterial(
        privateKeyBytes: privateKeyBytes,
        publicKeyBytes: remotePublicKey,
      );
      await _credentials.writeEd25519PrivateKey(userId, recovered.privateKeyBytes);
      await _credentials.writeEd25519PublicKey(userId, recovered.publicKeyBytes);
      return recovered;
    }

    // First-ever setup for this user: mint the one identity keypair and
    // escrow it. The server only ever sees the private key as ciphertext.
    final generated = await _signing.generateKeyPair();
    final encryptedPrivateKey = await _cipher.encryptBytes(generated.privateKeyBytes, payloadKeyBytes);
    await _profiles.upsertKeyMaterial(
      userId,
      salt: salt,
      publicKey: generated.publicKeyBytes,
      encryptedPrivateKey: encryptedPrivateKey,
    );
    await _credentials.writeEd25519PrivateKey(userId, generated.privateKeyBytes);
    await _credentials.writeEd25519PublicKey(userId, generated.publicKeyBytes);
    return generated;
  }

  /// Locks the vault: closes the database connection and explicitly zeroes
  /// the in-memory Tier-2 key material rather than just dropping the
  /// reference and waiting on the garbage collector.
  Future<void> lock() async {
    final fields = unlockedFieldsOf(state);
    if (fields != null) {
      await fields.vault.close();
      fields.payloadKeyBytes.fillRange(0, fields.payloadKeyBytes.length, 0);
    }
    state = const VaultLocked();
  }

  /// The sync controller drives these three transitions while the vault
  /// stays open the whole time — only the state *label* changes, so the UI
  /// (and [lock]) can react without the sync layer needing to know how to
  /// reconstruct a [VaultState].
  void markSyncing() => _transitionUnlockedLike((f) => VaultSyncing(
        vault: f.vault,
        payloadKeyBytes: f.payloadKeyBytes,
        signingKeyMaterial: f.signingKeyMaterial,
        deviceId: f.deviceId,
      ));

  void markUnlocked() => _transitionUnlockedLike((f) => VaultUnlocked(
        vault: f.vault,
        payloadKeyBytes: f.payloadKeyBytes,
        signingKeyMaterial: f.signingKeyMaterial,
        deviceId: f.deviceId,
      ));

  void markConflict() => _transitionUnlockedLike((f) => VaultSyncConflictDetected(
        vault: f.vault,
        payloadKeyBytes: f.payloadKeyBytes,
        signingKeyMaterial: f.signingKeyMaterial,
        deviceId: f.deviceId,
      ));

  void _transitionUnlockedLike(VaultState Function(UnlockedVaultFields) buildNext) {
    final fields = unlockedFieldsOf(state);
    if (fields == null) return;
    state = buildNext(fields);
  }
}
