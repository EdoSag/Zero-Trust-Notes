import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/secure_credentials_store.dart';
import '../../auth/application/auth_controller.dart';
import '../../vault/application/vault_controller.dart';
import '../../vault/application/vault_state.dart';
import '../data/encrypted_notes_api.dart';
import '../data/vault_snapshot_codec.dart';
import '../domain/sync_conflict.dart';

sealed class SyncUiState {
  const SyncUiState();
}

class SyncIdle extends SyncUiState {
  const SyncIdle();
}

class SyncEncrypting extends SyncUiState {
  const SyncEncrypting();
}

class SyncSyncing extends SyncUiState {
  const SyncSyncing();
}

class SyncOffline extends SyncUiState {
  const SyncOffline();
}

class SyncConflictPending extends SyncUiState {
  const SyncConflictPending(this.conflict);

  final SyncConflict conflict;
}

class SyncError extends SyncUiState {
  const SyncError(this.message);

  final String message;
}

final syncControllerProvider = NotifierProvider<SyncController, SyncUiState>(
  SyncController.new,
);

class SyncController extends Notifier<SyncUiState> {
  final _api = EncryptedNotesApi();
  final _codec = VaultSnapshotCodec();
  final _credentials = SecureCredentialsStore();
  final _connectivity = Connectivity();

  // Held between a detected push conflict and the user's resolution, so
  // "Overwrite Cloud Version" doesn't have to re-encrypt from scratch.
  String? _pendingPushBlobBase64;

  @override
  SyncUiState build() => const SyncIdle();

  /// Manual "Sync" button: encrypt + sign the whole local vault and push it
  /// as this user's snapshot — unless the cloud already has something newer
  /// than what this device last synced, in which case this pauses and asks.
  Future<void> push() async {
    final userId = ref.read(currentUserProvider)?.id;
    final unlocked = unlockedFieldsOf(ref.read(vaultControllerProvider));
    if (userId == null || unlocked == null) {
      state = const SyncError('Vault must be unlocked and signed in to sync.');
      return;
    }
    if (!await _isOnline()) {
      state = const SyncOffline();
      return;
    }

    final vaultController = ref.read(vaultControllerProvider.notifier);
    try {
      vaultController.markSyncing();
      state = const SyncEncrypting();
      final rows = await _codec.readAllNoteRows(unlocked.vault);
      final blob = await _codec.encodeAndSign(
        noteRows: rows,
        payloadKeyBytes: unlocked.payloadKeyBytes,
        signingKeyMaterial: unlocked.signingKeyMaterial,
      );

      state = const SyncSyncing();
      final localLastSync = await _credentials.readLastSyncTimestamp(userId);
      final remote = await _api.pull(userId);
      final remoteIsNewer = remote != null &&
          (localLastSync == null || remote.updatedAt.isAfter(localLastSync));

      if (remoteIsNewer) {
        _pendingPushBlobBase64 = blob;
        vaultController.markConflict();
        state = SyncConflictPending(
          SyncConflict(
            remoteUpdatedAt: remote.updatedAt,
            remoteDeviceId: remote.deviceId,
            localLastSyncTimestamp: localLastSync,
          ),
        );
        return;
      }

      await _pushBlob(userId: userId, deviceId: unlocked.deviceId, blob: blob);
      vaultController.markUnlocked();
      state = const SyncIdle();
    } catch (error) {
      vaultController.markUnlocked();
      state = SyncError('Sync failed: $error');
    }
  }

  /// Manual "Pull" button: fetch the cloud snapshot, verify its signature,
  /// and replace local note data with it wholesale (whole-blob last-write-
  /// wins — this is an explicit user action, so it doesn't itself trigger
  /// the conflict prompt the way an overwriting Push does).
  Future<void> pull() async {
    final userId = ref.read(currentUserProvider)?.id;
    final unlocked = unlockedFieldsOf(ref.read(vaultControllerProvider));
    if (userId == null || unlocked == null) {
      state = const SyncError('Vault must be unlocked and signed in to sync.');
      return;
    }
    if (!await _isOnline()) {
      state = const SyncOffline();
      return;
    }

    final vaultController = ref.read(vaultControllerProvider.notifier);
    try {
      vaultController.markSyncing();
      state = const SyncSyncing();

      final remote = await _api.pull(userId);
      if (remote == null) {
        vaultController.markUnlocked();
        state = const SyncIdle();
        return;
      }

      final noteRows = await _codec.verifyAndDecode(
        dataBlobBase64: remote.dataBlobBase64,
        payloadKeyBytes: unlocked.payloadKeyBytes,
        trustedPublicKeyBytes: unlocked.signingKeyMaterial.publicKeyBytes,
      );
      await _codec.applySnapshot(unlocked.vault, noteRows);
      await _credentials.writeLastSyncTimestamp(userId, remote.updatedAt);

      vaultController.markUnlocked();
      state = const SyncIdle();
    } catch (error) {
      vaultController.markUnlocked();
      state = SyncError('Pull failed: $error');
    }
  }

  /// Resolves a conflict surfaced by [push]: keep the cloud version (pull
  /// it down, discarding the prepared local push) or overwrite the cloud
  /// with what this device had already prepared to send.
  Future<void> resolveConflict({required bool keepCloudVersion}) async {
    final pendingBlob = _pendingPushBlobBase64;
    _pendingPushBlobBase64 = null;

    if (keepCloudVersion) {
      await pull();
      return;
    }

    final userId = ref.read(currentUserProvider)?.id;
    final unlocked = unlockedFieldsOf(ref.read(vaultControllerProvider));
    if (userId == null || unlocked == null || pendingBlob == null) {
      state = const SyncError('Sync failed: nothing pending to push.');
      return;
    }

    final vaultController = ref.read(vaultControllerProvider.notifier);
    try {
      await _pushBlob(userId: userId, deviceId: unlocked.deviceId, blob: pendingBlob);
      vaultController.markUnlocked();
      state = const SyncIdle();
    } catch (error) {
      vaultController.markUnlocked();
      state = SyncError('Sync failed: $error');
    }
  }

  /// Backs out of a pending conflict without pushing or pulling — the local
  /// vault keeps its unsynced changes exactly as they were.
  void cancelConflict() {
    _pendingPushBlobBase64 = null;
    ref.read(vaultControllerProvider.notifier).markUnlocked();
    state = const SyncIdle();
  }

  Future<void> _pushBlob({
    required String userId,
    required String deviceId,
    required String blob,
  }) async {
    final syncedAt = await _api.push(userId: userId, deviceId: deviceId, dataBlobBase64: blob);
    await _credentials.writeLastSyncTimestamp(userId, syncedAt);
  }

  Future<bool> _isOnline() async {
    final results = await _connectivity.checkConnectivity();
    return !results.contains(ConnectivityResult.none);
  }
}
