import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_notes/src/features/notebooks/application/notebooks_controller.dart';
import 'package:zerotrust_notes/src/features/notebooks/data/notebooks_repository.dart';
import 'package:zerotrust_notes/src/features/tags/application/tags_controller.dart';
import 'package:zerotrust_notes/src/features/tags/data/tags_repository.dart';

import '../../support/fake_sync_backend.dart';
import '../../support/notes_device.dart';

extension on Device {
  NotebooksRepository get notebooks => container.read(notebooksRepositoryProvider)!;
  TagsRepository get tags => container.read(tagsRepositoryProvider)!;
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

  test('notebooks, tags and filed notes reach the other device, and only notes list as notes', () async {
    final work = await phone.notebooks.create('Work');
    final urgent = await phone.tags.create('urgent', colorHex: '#FF0000');
    await phone.repo.createNote(title: 'Plan', body: 'ship', notebookId: work.id, tagIds: [urgent.id]);
    await phone.sync();
    await laptop.sync();

    expect([for (final n in await laptop.notebooks.fetchAll()) n.name], ['Work']);
    final tags = await laptop.tags.fetchAll();
    expect([for (final t in tags) (t.name, t.colorHex)], [('urgent', '#FF0000')]);
    final notes = await laptop.repo.fetchAll();
    expect(notes, hasLength(1));
    expect(notes.single.notebookId, work.id);
    expect(notes.single.tagIds, [urgent.id]);
  });

  test('renaming a notebook keeps its notes filed', () async {
    final work = await phone.notebooks.create('Work');
    await phone.repo.createNote(title: 'Plan', body: '', notebookId: work.id);
    await phone.notebooks.rename(work.id, 'Job');

    expect([for (final n in await phone.notebooks.fetchAll()) n.name], ['Job']);
    expect((await phone.repo.fetchAll()).single.notebookId, work.id);
  });

  test('deleting a notebook unfiles its notes, on every device', () async {
    final work = await phone.notebooks.create('Work');
    await phone.repo.createNote(title: 'Plan', body: '', notebookId: work.id);
    await phone.sync();
    await laptop.sync();

    await laptop.notebooks.delete(work.id);
    await laptop.sync();
    await phone.sync();

    expect(await phone.notebooks.fetchAll(), isEmpty);
    expect((await phone.repo.fetchAll()).single.notebookId, isNull);
  });

  test('deleting a tag takes it off every note', () async {
    final a = await phone.tags.create('a');
    final b = await phone.tags.create('b');
    await phone.repo.createNote(title: 'One', body: '', tagIds: [a.id, b.id]);

    await phone.tags.delete(a.id);

    expect([for (final t in await phone.tags.fetchAll()) t.name], ['b']);
    expect((await phone.repo.fetchAll()).single.tagIds, [b.id]);
  });

  test('saving a deleted note again brings it back (undo)', () async {
    final note = await phone.repo.createNote(title: 'Oops', body: 'keep me');
    await phone.repo.deleteNote(note.id);
    expect(await phone.notes(), isEmpty);

    await phone.repo.updateNote(note);
    await phone.sync();
    await laptop.sync();
    expect(await laptop.notes(), [('Oops', 'keep me')]);
  });

  test('a losing offline notebook rename takes the newer name, not a conflicted copy', () async {
    final work = await phone.notebooks.create('Work');
    await phone.sync();
    await laptop.sync();

    laptop.link.online = false;
    await laptop.notebooks.rename(work.id, 'From laptop');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await phone.notebooks.rename(work.id, 'From phone');
    await phone.sync();

    laptop.link.online = true;
    await laptop.sync();
    expect([for (final n in await laptop.notebooks.fetchAll()) n.name], ['From phone']);
    expect(await laptop.notes(), isEmpty);
  });
}
