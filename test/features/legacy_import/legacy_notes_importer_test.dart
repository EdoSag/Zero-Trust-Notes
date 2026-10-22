import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/src/core/crypto/payload_cipher_service.dart';
import 'package:zerotrust_notes/src/core/db/local_note_vault.dart';
import 'package:zerotrust_notes/src/features/legacy_import/legacy_notes_importer.dart';
import 'package:zerotrust_notes/src/features/notes/domain/note.dart';

import '../../support/fake_sync_backend.dart';

class FakeSource implements LegacyNotesSource {
  FakeSource(this.notes, {this.passphrase = 'old passphrase', this.present = true});
  final List<LegacyNote> notes;
  final String passphrase;
  final bool present;

  @override
  Future<bool> exists() async => present;

  @override
  Future<List<LegacyNote>> read(String passphrase) async {
    if (passphrase != this.passphrase) throw const WrongLegacyPassphrase();
    return notes;
  }
}

void main() {
  final cipher = PayloadCipherService();
  final oldKey = Uint8List.fromList(List.filled(32, 7));
  late ZtLocalStore store;
  late ItemSyncEngine engine;
  late FakeSyncBackend server;

  setUp(() async {
    final appKey = Uint8List.fromList(List.filled(32, 1));
    store = await ZtLocalStore.open(appKey: appKey);
    server = FakeSyncBackend();
    engine = await ItemSyncEngine.fromVault(
      appId: 'notes',
      appKey: appKey,
      deviceId: 'phone',
      store: store,
      backend: server,
    );
  });

  tearDown(() async {
    await engine.close();
    await store.close();
  });

  LegacyNotesImporter makeImporter(List<LegacyNotesSource> sources) => LegacyNotesImporter(
    sources: sources,
    engine: engine,
    ledger: store,
    deriveKey: (_) async => Uint8List.fromList(oldKey),
  );

  LegacyNote legacy(String id, String title) => LegacyNote(
    id: id,
    title: title,
    body: 'body of $title',
    notebookId: null,
    createdAt: DateTime.utc(2026, 3, 1),
  );

  Future<NoteRow> oldRow(String id, String title, {bool deleted = false}) async => NoteRow(
    id: id,
    notebookId: null,
    encryptedTitle: await cipher.encrypt(title, oldKey),
    encryptedBody: await cipher.encrypt('body', oldKey),
    createdAt: DateTime.utc(2026, 3, 1),
    updatedAt: DateTime.utc(2026, 3, 2),
    isDeleted: deleted,
    isDirty: false,
  );

  test('old rows decrypt with the old key; deleted ones are skipped', () async {
    final notes = await decryptLegacyRows([
      await oldRow('a', 'Kept'),
      await oldRow('b', 'Gone', deleted: true),
    ], oldKey);
    expect(notes.map((n) => n.title), ['Kept']);
    expect(notes.single.createdAt, DateTime.utc(2026, 3, 1));
  });

  test('the wrong old key is reported as a wrong passphrase', () async {
    final row = await oldRow('a', 'Kept');
    await expectLater(
      decryptLegacyRows([row], Uint8List(32)),
      throwsA(isA<WrongLegacyPassphrase>()),
    );
  });

  test('import re-encrypts old notes, queues them for sync, and runs once', () async {
    final importer = makeImporter([
        FakeSource([legacy('a', 'One'), legacy('b', 'Two')]),
      ]);
    expect(await importer.pendingSource(), isNotNull);

    expect(await importer.run('old passphrase'), 2);
    final a = await engine.store.get('a');
    expect(a!.json!['title'], 'One');
    expect(a.json!['createdAt'], DateTime.utc(2026, 3, 1).toIso8601String());
    expect(a.dirty, isTrue);
    // Dated before any real edit, so a newer version elsewhere always wins.
    expect(a.updatedAt, LegacyImporter.importedAt);

    expect((await engine.sync()).pushed, 2);
    expect(server.rows.keys, containsAll(['notes/a', 'notes/b']));

    expect(await importer.pendingSource(), isNull);
    expect(await importer.run('old passphrase'), 0);
  });

  test('a wrong passphrase imports nothing and can be retried', () async {
    final importer = makeImporter([
        FakeSource([legacy('a', 'One')]),
      ]);
    await expectLater(importer.run('nope'), throwsA(isA<WrongLegacyPassphrase>()));
    expect(await engine.store.get('a'), isNull);
    expect(await importer.pendingSource(), isNotNull);
    expect(await importer.run('old passphrase'), 1);
  });

  test('falls back to the next source and skips notes already synced here', () async {
    await engine.save(
      'a',
      Note.itemJson(
        title: 'Newer from another device',
        body: '',
        createdAt: DateTime.utc(2026, 3, 1),
      ),
    );
    final importer = makeImporter([
        FakeSource(const [], present: false),
        FakeSource([legacy('a', 'One'), legacy('b', 'Two')]),
      ]);
    expect(await importer.run('old passphrase'), 1);
    expect((await engine.store.get('a'))!.json!['title'], 'Newer from another device');
  });

  test('nothing to import when no source has data', () async {
    final importer = makeImporter([FakeSource(const [], present: false)]);
    expect(await importer.pendingSource(), isNull);
  });
}
