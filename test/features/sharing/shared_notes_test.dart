import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/src/features/notebooks/application/notebooks_controller.dart';
import 'package:zerotrust_notes/src/features/notebooks/domain/notebook.dart';
import 'package:zerotrust_notes/src/features/notes/application/notes_providers.dart';

import 'package:zerotrust_notes/src/features/sharing/shared_notebooks.dart';

import '../../support/sharing_people.dart';

void main() {
  late InMemorySpaceServer server;
  late Person a, b;

  setUp(() async {
    server = InMemorySpaceServer();
    a = Person(alice, server, 1);
    b = Person(bob, server, 7);
    await a.open();
    await b.open();
  });

  tearDown(() {
    a.c.dispose();
    b.c.dispose();
  });

  /// Alice invites Bob to [spaceId] and lets him in.
  Future<void> letBobIn(String spaceId) async {
    final link = await a.spaces.invite(spaceId);
    final join = await b.spaces.answer(SpaceInviteLink.parse('$link'), myName: 'Bob');
    final pending = await a.spaces.pendingJoins(spaceId);
    expect(pending.single.verificationCode, join.verificationCode);
    await a.spaces.confirm(pending.single);
    await a.syncSpaces();
    await b.syncSpaces();
  }

  test('a shared notebook: notes move in, both people read and edit them', () async {
    final trip = await a.c.read(notebooksRepositoryProvider)!.create('Trip');
    await a.device.repo.createNote(title: 'Packing', body: 'tent', notebookId: trip.id);
    await a.device.repo.createNote(
      title: 'Passwords',
      body: 'x',
      notebookId: trip.id,
      locked: true,
    );
    await a.device.repo.createNote(title: 'Other', body: '');

    final spaceId = await a.device.repo.shareNotebook(a.shared, trip, myName: 'Alice');
    await until(() => a.notes.length == 3 && a.notebooks.length == 1);
    final sharedId = Notebook.sharedId(spaceId);

    // The notebook and its note are now in the space; the locked note
    // stayed private and left the notebook; nothing is left behind.
    expect(a.notebooks.single.id, sharedId);
    expect(a.notebooks.single.name, 'Trip');
    expect(a.notebooks.single.shared!.isAdmin, isTrue);
    expect(a.note('Packing').spaceId, spaceId);
    expect(a.note('Packing').notebookId, sharedId);
    expect(a.note('Passwords').isShared, isFalse);
    expect(a.note('Passwords').notebookId, isNull);
    expect(a.note('Other').isShared, isFalse);
    final own = await a.device.repo.fetchAll();
    expect(own.map((n) => n.title), unorderedEquals(['Passwords', 'Other']));

    await letBobIn(spaceId);
    await until(() => b.notes.isNotEmpty, reason: 'Bob sees the shared note');
    expect(b.notebooks.single.name, 'Trip');
    expect(b.notebooks.single.shared!.isAdmin, isFalse);
    expect(b.note('Packing').body, 'tent');

    // Bob edits and adds; Alice sees both.
    await b.device.repo.updateNote(b.note('Packing').copyWith(body: 'tent, stove'));
    await b.device.repo.createNote(title: 'Route', body: 'north', notebookId: sharedId);
    await b.syncSpaces();
    await a.syncSpaces();
    await until(() => a.notes.any((n) => n.title == 'Route'));
    expect(a.note('Packing').body, 'tent, stove');
    expect(a.note('Route').spaceId, spaceId);
    // Not in Bob's own vault: only in the space.
    expect(await b.device.repo.fetchAll(), isEmpty);

    // Bob can't rename it: only owners can.
    await expectLater(b.shared.rename(spaceId, 'Mine'), throwsStateError);
    await a.shared.rename(spaceId, 'Trip 2026');
    await a.syncSpaces();
    await b.syncSpaces();
    await until(() => b.notebooks.single.name == 'Trip 2026');

    // Alice moves Route out: it's hers alone now, gone for Bob.
    await a.device.repo.updateNote(a.note('Route').copyWith(notebookId: null));
    await a.syncSpaces();
    await b.syncSpaces();
    await until(() => !b.notes.any((n) => n.title == 'Route'));
    expect(a.note('Route').isShared, isFalse);
    expect((await a.device.repo.fetchAll()).map((n) => n.title), contains('Route'));

    // Trash and delete reach the other person too.
    await b.device.repo.moveToTrash(b.note('Packing'));
    await b.syncSpaces();
    await a.syncSpaces();
    await until(() => a.note('Packing').isTrashed);
    expect(await a.device.repo.emptyTrash(), 1);
    await a.syncSpaces();
    await b.syncSpaces();
    await until(() => b.notes.isEmpty);
  });

  test('one note shared on its own stays in its space when edited', () async {
    final note = await a.device.repo.createNote(title: 'Groceries', body: 'milk');
    final spaceId = await a.device.repo.shareNote(
      a.shared,
      note,
      myName: 'Alice',
      name: 'Groceries',
    );
    await until(() => a.notes.length == 1 && a.notes.single.isShared);
    // Not a notebook: it shows in the main list.
    expect(a.notebooks, isEmpty);
    expect(a.notes.single.notebookId, isNull);
    expect(await a.device.repo.fetchAll(), isEmpty);

    await letBobIn(spaceId);
    await until(() => b.notes.isNotEmpty);
    final stored = await b.device.repo.updateNote(b.notes.single.copyWith(body: 'milk, eggs'));
    expect(stored.spaceId, spaceId, reason: 'still shared');
    await b.syncSpaces();
    await a.syncSpaces();
    await until(() => a.notes.single.body == 'milk, eggs');

    // A shared note is never stored locked: the lock is one person's own.
    await a.device.repo.updateNote(a.notes.single.copyWith(locked: true));
    await a.syncSpaces();
    await b.syncSpaces();
    expect(b.notes.single.locked, isFalse);
  });

  test('sharing items in the account store are never read as notes', () async {
    final note = await a.device.repo.createNote(title: 'Solo', body: '');
    await a.device.repo.shareNote(a.shared, note, myName: 'Alice', name: 'Solo');
    await until(() => a.notes.length == 1);
    // The space anchor and the sharing name live in the account's store
    // but are never read as notes.
    final ownItems = await a.c.read(notesStoreProvider.future).then((s) => s.liveItems());
    expect(ownItems.map((i) => i.json?['kind']), everyElement(isNotNull));
    expect(a.notes.single.title, 'Solo');
  });
  test('a read still running when the vault locks shows nothing afterwards', () async {
    final trip = await a.c.read(notebooksRepositoryProvider)!.create('Trip');
    await a.device.repo.createNote(title: 'Packing', body: 'tent', notebookId: trip.id);
    await a.device.repo.shareNotebook(a.shared, trip, myName: 'Alice');
    await until(() => a.notes.length == 1);

    // The vault locks while the space's notes are being read.
    a.copies.stores.values.single.beforeRead = () async {
      a.c.read(vaultControllerProvider.notifier).lock();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    };
    await a.shared.reload();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final state = a.c.read(sharedNotesProvider);
    expect(state.notes, isEmpty, reason: 'nothing from before the lock is published');
    expect(state.notebooks, isEmpty);
  });
}
