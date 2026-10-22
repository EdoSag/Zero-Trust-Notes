import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/src/core/crypto/payload_cipher_service.dart';
import 'package:zerotrust_notes/src/core/db/local_note_vault.dart';
import 'package:zerotrust_notes/src/core/errors/vault_exceptions.dart';
import 'package:zerotrust_notes/src/features/legacy_import/legacy_notes_importer.dart';
import 'package:zerotrust_notes/src/features/legacy_import/previous_store_migration.dart';

import '../../support/fake_sync_backend.dart';

/// `notes_v2.sqlite`, in memory: opens only with the key it was made with.
class FakePreviousFile implements PreviousNotesStoreFile {
  FakePreviousFile(this.vault, this.key);
  final LocalNoteVault vault;
  final String key;
  bool deleted = false;

  @override
  Future<bool> exists() async => !deleted;

  @override
  Future<LocalNoteVault> open(String key) async {
    if (key != this.key) throw VaultInitializationException('wrong key');
    return vault;
  }

  @override
  Future<void> delete() async => deleted = true;
}

String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  // Each test makes its own in-memory database.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final cipher = PayloadCipherService();
  final appKey = Uint8List.fromList(List.generate(32, (i) => i + 1));
  late ZtLocalStore store;
  late LocalNoteVault old;
  late FakePreviousFile file;
  late Uint8List columnKey;

  setUp(() async {
    store = await ZtLocalStore.open(appKey: appKey);
    old = LocalNoteVault.forTesting(NativeDatabase.memory());
    file = FakePreviousFile(old, hex(await Kdf.hkdf(appKey, 'zt/notes/db/v1')));
    columnKey = await Kdf.hkdf(appKey, 'zt/notes/columns/v1');
  });

  tearDown(() => store.close());

  Future<void> addOld(
    String id,
    String title, {
    required int micros,
    bool dirty = false,
    bool deleted = false,
  }) async => old
      .into(old.notes)
      .insert(
        NotesCompanion.insert(
          id: id,
          encryptedTitle: await cipher.encrypt(title, columnKey),
          encryptedBody: await cipher.encrypt('body of $title', columnKey),
          createdAt: DateTime.utc(2026, 10, 1),
          updatedAt: DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true),
          isDeleted: Value(deleted),
          isDirty: Value(dirty),
          updatedAtMicros: Value(micros),
        ),
      );

  final t = DateTime.utc(2026, 10, 20, 9, 0, 0, 0, 123).microsecondsSinceEpoch;

  test('moves notes with their edit times and unsynced edits, then deletes the file', () async {
    await addOld('synced', 'Synced', micros: t);
    await addOld('unsynced', 'Typed offline', micros: t + 1, dirty: true);
    await addOld('gone', 'Deleted offline', micros: t + 2, dirty: true, deleted: true);

    expect(await movePreviousNotesStore(store: store, appKey: appKey, file: file), 3);

    final synced = (await store.get('synced'))!;
    expect(synced.json, {
      'title': 'Synced',
      'body': 'body of Synced',
      'notebookId': null,
      'createdAt': DateTime.utc(2026, 10, 1).toIso8601String(),
    });
    expect(synced.updatedAt.microsecondsSinceEpoch, t);
    expect(synced.dirty, isFalse);
    expect((await store.dirtyItems()).map((i) => i.itemId), unorderedEquals(['unsynced', 'gone']));
    expect((await store.get('gone'))!.deleted, isTrue);
    expect(file.deleted, isTrue);

    // The unsynced edits go up on the next sync.
    final engine = await ItemSyncEngine.fromVault(
      appId: 'notes',
      appKey: appKey,
      deviceId: 'phone',
      store: store,
      backend: FakeSyncBackend(),
    );
    addTearDown(engine.close);
    expect((await engine.sync()).pushed, 2);

    // Once per account.
    file.deleted = false;
    expect(await movePreviousNotesStore(store: store, appKey: appKey, file: file), 0);
  });

  test('a newer version already in the store is kept', () async {
    await addOld('a', 'Old', micros: t, dirty: true);
    await store.put(
      LocalItem(
        itemId: 'a',
        updatedAt: DateTime.fromMicrosecondsSinceEpoch(t + 5, isUtc: true),
        json: {'title': 'Newer'},
      ),
    );
    expect(await movePreviousNotesStore(store: store, appKey: appKey, file: file), 0);
    expect((await store.get('a'))!.json!['title'], 'Newer');
  });

  test('a finished pre-core import stays finished', () async {
    await old
        .into(old.syncMeta)
        .insert(SyncMetaCompanion.insert(key: 'legacy_import_done_at', value: '2026-10-18'));
    await movePreviousNotesStore(store: store, appKey: appKey, file: file);
    expect(await store.legacyImportDone(LegacyNotesImporter.source), isTrue);
  });

  test("a file this key can't open is left alone and retried later", () async {
    await addOld('a', 'Not mine', micros: t);
    final otherKey = Uint8List.fromList(List.filled(32, 9));
    expect(await movePreviousNotesStore(store: store, appKey: otherKey, file: file), 0);
    expect(await store.get('a'), isNull);
    expect(file.deleted, isFalse);
    expect(await store.legacyImportDone(LegacyNotesImporter.source), isFalse);
    // Not recorded as done: the next unlock tries again.
    expect(await store.legacyImportDone('notes-v2-store'), isFalse);
  });

  test('no file: nothing to move', () async {
    file.deleted = true;
    expect(await movePreviousNotesStore(store: store, appKey: appKey, file: file), 0);
    expect(await store.all(), isEmpty);
  });
}
