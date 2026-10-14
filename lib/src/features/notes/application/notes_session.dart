import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../../../core/db/local_note_vault.dart';
import '../../../core/storage/secure_credentials_store.dart';
import '../../sync/data/notes_item_store.dart';
import '../data/notes_repository.dart';
import '../domain/note.dart';

/// Everything that exists only while the account vault is unlocked: the
/// open local database, its keys, and the sync engine.
class NotesSession {
  NotesSession({
    required this.vault,
    required this.columnKey,
    required this.engine,
    required this.repository,
  });

  final LocalNoteVault vault;
  final Uint8List columnKey;
  final ItemSyncEngine engine;
  final NotesRepository repository;
}

/// Overridable seams, so tests can run without Supabase or a device.
final syncBackendProvider = Provider<SyncBackend>((ref) => SupabaseSyncBackend());

final deviceIdProvider = FutureProvider<String>((ref) => SecureCredentialsStore().ensureDeviceId());

final openNotesVaultProvider = Provider<Future<LocalNoteVault> Function(String key)>(
  (ref) =>
      (key) =>
          LocalNoteVault.open(passphrase: key, fileBaseName: LocalNoteVault.currentFileBaseName),
);

/// Bumped after every local change; the sync controller listens to it.
final notesChangedProvider = NotifierProvider<NotesChanged, int>(NotesChanged.new);

class NotesChanged extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// `null` whenever the vault is locked. Rebuilt (and the old database
/// closed, its keys zeroed) every time the vault locks or unlocks.
final notesSessionProvider = FutureProvider<NotesSession?>((ref) async {
  final vaultState = ref.watch(vaultControllerProvider);
  if (vaultState is! VaultUnlocked) return null;

  // Copies, so this session owns key material it can zero on dispose.
  final appKey = Uint8List.fromList(vaultState.appKey);
  final dbKey = await Kdf.hkdf(appKey, 'zt/notes/db/v1');
  final columnKey = await Kdf.hkdf(appKey, 'zt/notes/columns/v1');
  final deviceId = await ref.watch(deviceIdProvider.future);

  final vault = await ref.read(openNotesVaultProvider)(_hex(dbKey));
  dbKey.fillRange(0, dbKey.length, 0);

  final engine = ItemSyncEngine(
    appId: 'notes',
    appKey: appKey,
    deviceId: deviceId,
    store: NotesItemStore(vault: vault, columnKey: columnKey),
    backend: ref.read(syncBackendProvider),
    signingKeys: await KeyHierarchy.signingKeys(appKey),
  );
  ref.onDispose(() async {
    await engine.stopLive();
    await vault.close();
    appKey.fillRange(0, appKey.length, 0);
    columnKey.fillRange(0, columnKey.length, 0);
  });

  return NotesSession(
    vault: vault,
    columnKey: columnKey,
    engine: engine,
    repository: NotesRepository(
      vault: vault,
      columnKey: columnKey,
      engine: engine,
      onChanged: () => ref.read(notesChangedProvider.notifier).bump(),
    ),
  );
});

/// `null` whenever the vault isn't unlocked — callers must treat that as
/// "no notes access", not as an empty vault.
final notesRepositoryProvider = Provider<NotesRepository?>(
  (ref) => ref.watch(notesSessionProvider).value?.repository,
);

final notesListProvider = StreamProvider<List<Note>>((ref) {
  final repository = ref.watch(notesRepositoryProvider);
  if (repository == null) return const Stream.empty();
  return repository.watchAll();
});

String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
