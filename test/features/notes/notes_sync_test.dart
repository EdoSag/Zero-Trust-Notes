import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/main.dart';
import 'package:zerotrust_notes/src/core/db/local_note_vault.dart';
import 'package:zerotrust_notes/src/features/notes/application/notes_session.dart';
import 'package:zerotrust_notes/src/features/sync/application/sync_controller.dart';

import '../../support/fake_sync_backend.dart';

/// One install of the app: its own in-memory database and device id, on a
/// shared fake server, unlocked with the same account key.
class Device {
  Device(this.id, FakeSyncBackend server) {
    container = ProviderContainer(
      overrides: [
        ztAppConfigProvider.overrideWithValue(notesAppConfig),
        syncBackendProvider.overrideWithValue(server),
        deviceIdProvider.overrideWith((ref) async => id),
        isOnlineProvider.overrideWithValue(() async => true),
        openNotesVaultProvider.overrideWithValue((key) async {
          openedWithKey = key;
          return LocalNoteVault.forTesting(NativeDatabase.memory());
        }),
      ],
    );
  }

  final String id;
  late final ProviderContainer container;
  String? openedWithKey;

  Future<NotesSession> unlock() async {
    container.listen(syncControllerProvider, (_, _) {});
    await container
        .read(vaultControllerProvider.notifier)
        .unlock(Uint8List.fromList(List.generate(32, (i) => i)));
    final session = await container.read(notesSessionProvider.future);
    return session!;
  }

  Future<List<(String, String)>> notes() async {
    final all = await container.read(notesRepositoryProvider)!.fetchAll();
    return [for (final n in all) (n.title, n.body)];
  }

  Future<void> sync() => container.read(syncControllerProvider.notifier).syncNow();
}

void main() {
  late FakeSyncBackend server;
  late Device phone;
  late Device laptop;

  setUp(() async {
    server = FakeSyncBackend();
    phone = Device('phone', server);
    laptop = Device('laptop', server);
    await phone.unlock();
    await laptop.unlock();
  });

  tearDown(() {
    phone.container.dispose();
    laptop.container.dispose();
  });

  test('a note written on one device appears on another', () async {
    await phone.container
        .read(notesRepositoryProvider)!
        .createNote(title: 'Groceries', body: 'milk');
    await phone.sync();
    await laptop.sync();

    expect(await laptop.notes(), [('Groceries', 'milk')]);
  });

  test('note content is encrypted locally and on the server', () async {
    final session = await phone.container.read(notesSessionProvider.future);
    await session!.repository.createNote(title: 'Secret plan', body: 'launch at dawn');
    await phone.sync();

    final row = await session.vault.select(session.vault.notes).getSingle();
    expect(String.fromCharCodes(row.encryptedTitle), isNot(contains('Secret')));
    expect(String.fromCharCodes(row.encryptedBody), isNot(contains('dawn')));
    final remote = server.rows.values.single;
    expect(String.fromCharCodes(remote.dataBlob!), isNot(contains('Secret')));

    // The database key is derived from the account, never the raw app key.
    expect(phone.openedWithKey, hasLength(64));
  });

  test('edits and deletes reach the other device', () async {
    final repo = phone.container.read(notesRepositoryProvider)!;
    final note = await repo.createNote(title: 'Draft', body: 'v1');
    await phone.sync();
    await laptop.sync();

    await repo.updateNote(note.copyWith(body: 'v2'));
    await phone.sync();
    await laptop.sync();
    expect(await laptop.notes(), [('Draft', 'v2')]);

    await repo.deleteNote(note.id);
    await phone.sync();
    await laptop.sync();
    expect(await laptop.notes(), isEmpty);
  });

  test('two quick edits within one second still reach the other device', () async {
    final repo = phone.container.read(notesRepositoryProvider)!;
    final note = await repo.createNote(title: 'Quick', body: 'a');
    await phone.sync();
    await laptop.sync();
    await repo.updateNote(note.copyWith(body: 'b'));
    await phone.sync();
    await laptop.sync();

    expect(await laptop.notes(), [('Quick', 'b')]);
  });

  test('a losing offline edit is kept as a conflicted copy', () async {
    final phoneRepo = phone.container.read(notesRepositoryProvider)!;
    final note = await phoneRepo.createNote(title: 'Trip', body: 'v1');
    await phone.sync();
    await laptop.sync();

    // Laptop edits first but doesn't sync; phone edits later and syncs.
    final laptopRepo = laptop.container.read(notesRepositoryProvider)!;
    await laptopRepo.updateNote(note.copyWith(body: 'from laptop'));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await phoneRepo.updateNote(note.copyWith(body: 'from phone'));
    await phone.sync();

    await laptop.sync();
    final laptopNotes = await laptop.notes();
    expect(
      laptopNotes,
      containsAll([('Trip', 'from phone'), ('Trip (conflicted copy)', 'from laptop')]),
    );

    // The copy syncs back to the phone too.
    await laptop.sync();
    await phone.sync();
    expect(await phone.notes(), containsAll(laptopNotes));
  });

  test('locking closes the session and hides notes', () async {
    expect(phone.container.read(notesRepositoryProvider), isNotNull);
    phone.container.read(vaultControllerProvider.notifier).lock();
    expect(await phone.container.read(notesSessionProvider.future), isNull);
    expect(phone.container.read(notesRepositoryProvider), isNull);
  });
}
