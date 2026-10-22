import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/src/features/notes/application/notes_providers.dart';
import 'package:zerotrust_notes/src/features/notes/data/notes_repository.dart';
import 'package:zerotrust_notes/src/features/sync/application/conflict_copies.dart';

import '../../support/fake_sync_backend.dart';
import '../../support/notes_overrides.dart';

/// The shared server as one device reaches it: unreachable while [online]
/// is off.
class DeviceLink implements SyncBackend {
  DeviceLink(this.server);
  final FakeSyncBackend server;
  bool online = true;

  void _check() {
    if (!online) throw Exception('offline');
  }

  @override
  Future<List<RemoteItem>> pull(String app, {DateTime? since}) async {
    _check();
    return server.pull(app, since: since);
  }

  @override
  Future<List<RemoteItem>> fetch(String app, Set<String> itemIds) async {
    _check();
    return server.fetch(app, itemIds);
  }

  @override
  Future<Set<String>> pushAll(String app, List<RemoteItem> items) async {
    _check();
    return server.pushAll(app, items);
  }

  @override
  Future<void> Function() subscribe(String app, void Function(RemoteItem) onChange) =>
      server.subscribe(app, onChange);
}

/// One install of the app: its own in-memory store and device id, on a
/// shared fake server, unlocked with the same account key.
class Device {
  Device(String id, FakeSyncBackend server) : link = DeviceLink(server) {
    container = ProviderContainer(
      overrides: notesTestOverrides(server: link, deviceId: id),
    );
  }

  final DeviceLink link;
  late final ProviderContainer container;

  Future<void> unlock() async {
    // As the notes list does: keep sync and conflict copies running.
    container.listen(ztSyncControllerProvider, (_, _) {});
    container.listen(conflictCopiesProvider, (_, _) {});
    await container
        .read(vaultControllerProvider.notifier)
        .unlock(Uint8List.fromList(List.generate(32, (i) => i)));
    await container.read(notesStoreProvider.future);
    await container.read(ztSyncEngineProvider.future);
  }

  NotesRepository get repo => container.read(notesRepositoryProvider)!;

  Future<List<(String, String)>> notes() async {
    final all = await repo.fetchAll();
    return [for (final n in all) (n.title, n.body)];
  }

  Future<void> sync() async {
    await container.read(ztSyncControllerProvider.notifier).syncNow();
    // Let conflict copies land.
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

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
