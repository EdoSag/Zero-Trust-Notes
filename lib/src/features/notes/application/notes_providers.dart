import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../../legacy_import/previous_store_migration.dart';
import '../data/notes_repository.dart';
import '../domain/note.dart';

/// Overridable so tests don't touch the documents directory.
final previousNotesStoreFileProvider = Provider<PreviousNotesStoreFile>(
  (ref) => DocumentsPreviousNotesStoreFile(),
);

/// The account's encrypted local store, open while the vault is unlocked,
/// once the notes of the earlier Notes store are in it. Watch this, not
/// `ztLocalStoreProvider`, so nothing syncs before they are.
final notesStoreProvider = FutureProvider<ZtLocalStore>((ref) async {
  final unlocked = ref.watch(
    vaultControllerProvider.select((s) => s is VaultUnlocked ? s.appKey : null),
  );
  if (unlocked == null) throw const VaultIsLocked();
  // Copy before any await: locking zeroes the vault's buffer.
  final appKey = Uint8List.fromList(unlocked);
  try {
    final store = await ref.watch(ztLocalStoreProvider.future);
    if (store is! ZtLocalStore) {
      throw StateError('Notes needs the shared ZtLocalStore, got ${store.runtimeType}');
    }
    await movePreviousNotesStore(
      store: store,
      appKey: appKey,
      file: ref.read(previousNotesStoreFileProvider),
    );
    return store;
  } finally {
    appKey.fillRange(0, appKey.length, 0);
  }
});

/// `null` whenever the vault isn't unlocked (or the store is still
/// opening). Callers must treat that as "no notes access", not as an empty
/// vault.
final notesRepositoryProvider = Provider<NotesRepository?>((ref) {
  // Not `.value`: that keeps the last (closed) store while locked.
  final store = switch (ref.watch(notesStoreProvider)) {
    AsyncData(:final value) => value,
    _ => null,
  };
  if (store == null) return null;
  return NotesRepository(
    store: store,
    sync: () async {
      await ref.read(ztSyncEngineProvider.future);
      return ref.read(ztSyncControllerProvider.notifier);
    },
  );
});

final notesListProvider = StreamProvider<List<Note>>((ref) {
  final repository = ref.watch(notesRepositoryProvider);
  if (repository == null) return const Stream.empty();
  return repository.watchAll();
});
