import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/src/features/keep_import/keep_importer.dart';
import 'package:zerotrust_notes/src/features/keep_import/keep_takeout_parser.dart';
import 'package:zerotrust_notes/src/features/notes/application/notes_providers.dart';
import 'package:zerotrust_notes/src/features/notes/data/notes_repository.dart';
import 'package:zerotrust_notes/src/features/notes/domain/note_color.dart';
import 'package:zerotrust_notes/src/features/tags/application/tags_controller.dart';

import '../../support/fake_sync_backend.dart';
import '../../support/notes_device.dart';

List<int> keepJson(Map<String, Object?> json) => utf8.encode(jsonEncode(json));

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

  group('Trash', () {
    late DateTime now;
    late NotesRepository repo;

    setUp(() async {
      now = DateTime.utc(2026, 11, 1);
      repo = NotesRepository(
        store: await phone.container.read(notesStoreProvider.future),
        sync: () async => phone.container.read(ztSyncControllerProvider.notifier),
        clock: () => now,
      );
    });

    test('a trashed note keeps its text, loses pin and reminder, and restores', () async {
      final created = await repo.createNote(
        title: 'Plan',
        body: 'ship',
        pinned: true,
        reminderAt: DateTime.utc(2027),
      );
      await repo.moveToTrash(created);
      final trashed = (await repo.fetchAll()).single;
      expect(trashed.isTrashed, isTrue);
      expect(trashed.pinned, isFalse);
      expect(trashed.reminderAt, isNull);
      expect(trashed.body, 'ship');

      await repo.restoreFromTrash(trashed);
      expect((await repo.fetchAll()).single.isTrashed, isFalse);
    });

    test('notes in Trash for 30 days are deleted for good, on every device', () async {
      final old = await repo.createNote(title: 'Old', body: '');
      final recent = await repo.createNote(title: 'Recent', body: '');
      await repo.moveToTrash(old);
      now = now.add(const Duration(days: 20));
      await repo.moveToTrash(recent);
      now = now.add(const Duration(days: 11));

      expect(await repo.purgeExpiredTrash(), 1);
      expect([for (final n in await repo.fetchAll()) n.title], ['Recent']);

      await phone.sync();
      await laptop.sync();
      expect([for (final n in await laptop.repo.fetchAll()) n.title], ['Recent']);
    });

    test('empty Trash deletes only trashed notes', () async {
      final a = await repo.createNote(title: 'A', body: '');
      await repo.createNote(title: 'B', body: '');
      await repo.moveToTrash(a);
      expect(await repo.emptyTrash(), 1);
      expect([for (final n in await repo.fetchAll()) n.title], ['B']);
    });

    test('pin, colour and archive reach the other device', () async {
      final created = await phone.repo.createNote(title: 'Plan', body: '');
      await phone.repo.updateNote(created.copyWith(pinned: true, color: NoteColor.yellow));
      await phone.sync();
      await laptop.sync();
      final there = (await laptop.repo.fetchAll()).single;
      expect(there.pinned, isTrue);
      expect(there.color, NoteColor.yellow);
    });
  });

  group('Google Keep import', () {
    final files = {
      'Shopping.json': keepJson({
        'color': 'GREEN',
        'isTrashed': false,
        'isPinned': true,
        'isArchived': false,
        'title': 'Shopping',
        'listContent': [
          {'text': 'milk', 'isChecked': true},
          {'text': 'eggs', 'isChecked': false},
        ],
        'labels': [
          {'name': 'Home'},
        ],
        'createdTimestampUsec': 1700000000000000,
        'userEditedTimestampUsec': 1700000100000000,
      }),
      'Idea.json': keepJson({
        'color': 'DEFAULT',
        'isTrashed': false,
        'isPinned': false,
        'isArchived': true,
        'title': '',
        'textContent': 'A thought',
        'labels': [
          {'name': 'home'},
          {'name': 'Ideas'},
        ],
        'attachments': [
          {'filePath': 'x.jpg', 'mimetype': 'image/jpeg'},
        ],
        'createdTimestampUsec': 1700000200000000,
      }),
      'Deleted.json': keepJson({
        'isTrashed': true,
        'title': 'Nope',
        'textContent': 'bin',
        'createdTimestampUsec': 1700000300000000,
      }),
      'Labels.txt': utf8.encode('Home\nIdeas'),
    };

    test('reads Keep notes from a Takeout zip, ignoring other products', () {
      final archive = Archive();
      for (final MapEntry(:key, :value) in files.entries) {
        archive.addFile(ArchiveFile.bytes('Takeout/Keep/$key', value));
      }
      archive.addFile(
        ArchiveFile.bytes('Takeout/Tasks/Tasks.json', keepJson({'title': 'not keep', 'textContent': 'x'})),
      );
      final zip = ZipEncoder().encodeBytes(archive);

      final notes = const KeepTakeoutParser().parseFiles({'takeout-1.zip': zip});
      expect(notes, hasLength(3));
      final shopping = notes.firstWhere((n) => n.title == 'Shopping');
      expect(shopping.color, NoteColor.green);
      expect(shopping.pinned, isTrue);
      expect([for (final i in shopping.checklist!) (i.text, i.checked)], [('eggs', false), ('milk', true)]);
      expect(shopping.createdAt, DateTime.fromMicrosecondsSinceEpoch(1700000000000000, isUtc: true));
    });

    test('imports labels as tags, skips Keep trash, and a second run adds nothing', () async {
      final tags = phone.container.read(tagsRepositoryProvider)!;
      await tags.create('Home');
      final importer = KeepImporter(notes: phone.repo, tags: tags);
      final parsed = const KeepTakeoutParser().parseFiles(files);

      final first = await importer.run(parsed);
      expect(first.imported, 2);
      expect(first.skippedTrashed, 1);
      expect(first.attachmentsNotImported, 1);

      final allTags = await tags.fetchAll();
      expect([for (final t in allTags) t.name], ['Home', 'Ideas']); // "home" matched "Home"
      final notes = await phone.repo.fetchAll();
      final idea = notes.firstWhere((n) => n.body == 'A thought');
      expect(idea.archived, isTrue);
      expect(idea.tagIds, hasLength(2));
      final shopping = notes.firstWhere((n) => n.title == 'Shopping');
      expect(shopping.isChecklist, isTrue);
      expect(shopping.pinned, isTrue);
      expect(shopping.color, NoteColor.green);

      final second = await importer.run(parsed);
      expect(second.imported, 0);
      expect(second.skippedDuplicates, 2);
      expect(await phone.repo.fetchAll(), hasLength(2));
    });
  });
}
