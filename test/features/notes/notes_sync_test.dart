import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/src/features/notes/application/notes_providers.dart';

import '../../support/fake_sync_backend.dart';
import '../../support/notes_device.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    await phone.repo.createNote(title: 'Groceries', body: 'milk');
    await phone.sync();
    await laptop.sync();

    expect(await laptop.notes(), [('Groceries', 'milk')]);
  });

  test('note content is sealed on the server', () async {
    await phone.repo.createNote(title: 'Secret plan', body: 'launch at dawn');
    await phone.sync();

    final remote = server.rows.values.single;
    expect(String.fromCharCodes(remote.dataBlob!), isNot(contains('Secret')));
    expect(String.fromCharCodes(remote.dataBlob!), isNot(contains('dawn')));
  });

  test('edits and deletes reach the other device', () async {
    final note = await phone.repo.createNote(title: 'Draft', body: 'v1');
    await phone.sync();
    await laptop.sync();

    await phone.repo.updateNote(note.copyWith(body: 'v2'));
    await phone.sync();
    await laptop.sync();
    expect(await laptop.notes(), [('Draft', 'v2')]);

    await phone.repo.deleteNote(note.id);
    await phone.sync();
    await laptop.sync();
    expect(await laptop.notes(), isEmpty);
  });

  test('the list updates as notes change', () async {
    final lists = <List<String>>[];
    phone.container.listen(
      notesListProvider,
      (_, next) => lists.add([for (final n in next.value ?? const []) n.title]),
      fireImmediately: true,
    );
    await phone.repo.createNote(title: 'One', body: '');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await phone.repo.createNote(title: 'Two', body: '');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(lists.last, ['Two', 'One']);
  });

  test('a losing offline edit is kept as a conflicted copy', () async {
    final note = await phone.repo.createNote(title: 'Trip', body: 'v1');
    await phone.sync();
    await laptop.sync();

    // Laptop edits first but doesn't sync; phone edits later and syncs.
    laptop.link.online = false;
    await laptop.repo.updateNote(note.copyWith(body: 'from laptop'));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await phone.repo.updateNote(note.copyWith(body: 'from phone'));
    await phone.sync();

    laptop.link.online = true;
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

  test('an edit made offline syncs once the network is back', () async {
    phone.link.online = false;
    await phone.repo.createNote(title: 'Offline', body: 'x');
    await phone.sync();
    expect(phone.container.read(ztSyncControllerProvider).error, isNotNull);

    phone.link.online = true;
    await phone.sync();
    expect(phone.container.read(ztSyncControllerProvider).error, isNull);
    await laptop.sync();
    expect(await laptop.notes(), contains(('Offline', 'x')));
  });

  test('locking closes the store and hides notes', () async {
    phone.container.listen(notesRepositoryProvider, (_, _) {});
    expect(phone.container.read(notesRepositoryProvider), isNotNull);
    phone.container.read(vaultControllerProvider.notifier).lock();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(phone.container.read(notesStoreProvider).error, isA<VaultIsLocked>());
    expect(phone.container.read(notesRepositoryProvider), isNull);
  });
}
