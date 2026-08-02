import 'dart:typed_data';

import '../../../core/crypto/signing_service.dart';
import '../../../core/db/local_note_vault.dart';

/// Explicit vault lifecycle. The app always restarts at [VaultLocked] on a
/// cold start — an active Supabase session (added in M3) never implies an
/// unlocked vault.
sealed class VaultState {
  const VaultState();
}

class VaultLocked extends VaultState {
  const VaultLocked();
}

class VaultUnlocking extends VaultState {
  const VaultUnlocking();
}

class VaultUnlocked extends VaultState {
  const VaultUnlocked({
    required this.vault,
    required this.payloadKeyBytes,
    required this.signingKeyMaterial,
    required this.deviceId,
  });

  final LocalNoteVault vault;

  /// Raw Tier-2 AES-256-GCM key material. Held only in memory for the
  /// lifetime of this state; explicitly zeroed by the vault controller
  /// when the vault locks.
  final Uint8List payloadKeyBytes;

  /// This device's Ed25519 identity, used from M3 onward to sign outgoing
  /// sync payloads. The private key bytes never leave the device.
  final Ed25519KeyMaterial signingKeyMaterial;

  /// Stable per-install id, used from M3 onward to tag sync payloads.
  final String deviceId;
}

class VaultSyncing extends VaultState {
  const VaultSyncing({
    required this.vault,
    required this.payloadKeyBytes,
    required this.signingKeyMaterial,
    required this.deviceId,
  });

  final LocalNoteVault vault;
  final Uint8List payloadKeyBytes;
  final Ed25519KeyMaterial signingKeyMaterial;
  final String deviceId;
}

class VaultSyncConflictDetected extends VaultState {
  const VaultSyncConflictDetected({
    required this.vault,
    required this.payloadKeyBytes,
    required this.signingKeyMaterial,
    required this.deviceId,
  });

  final LocalNoteVault vault;
  final Uint8List payloadKeyBytes;
  final Ed25519KeyMaterial signingKeyMaterial;
  final String deviceId;
}

class VaultError extends VaultState {
  const VaultError(this.message);

  final String message;
}

/// The fields shared by every state where the vault is actually open —
/// [VaultUnlocked], [VaultSyncing], and [VaultSyncConflictDetected] repeat
/// the same four fields rather than sharing a base class, so that a
/// `switch` on [VaultState] stays exhaustively checkable by the compiler.
/// This is the one place that flattens them back out for callers (the sync
/// layer, in particular) that need the fields without caring which of the
/// three "open" states the vault happens to be in.
typedef UnlockedVaultFields = ({
  LocalNoteVault vault,
  Uint8List payloadKeyBytes,
  Ed25519KeyMaterial signingKeyMaterial,
  String deviceId,
});

UnlockedVaultFields? unlockedFieldsOf(VaultState state) {
  return switch (state) {
    VaultUnlocked(:final vault, :final payloadKeyBytes, :final signingKeyMaterial, :final deviceId) =>
      (vault: vault, payloadKeyBytes: payloadKeyBytes, signingKeyMaterial: signingKeyMaterial, deviceId: deviceId),
    VaultSyncing(:final vault, :final payloadKeyBytes, :final signingKeyMaterial, :final deviceId) =>
      (vault: vault, payloadKeyBytes: payloadKeyBytes, signingKeyMaterial: signingKeyMaterial, deviceId: deviceId),
    VaultSyncConflictDetected(:final vault, :final payloadKeyBytes, :final signingKeyMaterial, :final deviceId) =>
      (vault: vault, payloadKeyBytes: payloadKeyBytes, signingKeyMaterial: signingKeyMaterial, deviceId: deviceId),
    _ => null,
  };
}
