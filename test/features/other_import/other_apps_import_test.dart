import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/src/features/export/application/markdown_folder_export.dart';
import 'package:zerotrust_notes/src/features/notebooks/application/notebooks_controller.dart';
import 'package:zerotrust_notes/src/features/notes/domain/note.dart';
import 'package:zerotrust_notes/src/features/other_import/evernote_parser.dart';
import 'package:zerotrust_notes/src/features/other_import/imported_note.dart';
import 'package:zerotrust_notes/src/features/other_import/markdown_folder_parser.dart';
import 'package:zerotrust_notes/src/features/other_import/other_apps_importer.dart';
import 'package:zerotrust_notes/src/features/other_import/other_apps_parser.dart';
import 'package:zerotrust_notes/src/features/other_import/standard_notes_parser.dart';
import 'package:zerotrust_notes/src/features/tags/application/tags_controller.dart';

import '../../support/fake_sync_backend.dart';
import '../../support/notes_device.dart';

List<int> _utf8(String s) => utf8.encode(s);

Uint8List _zip(Map<String, List<int>> files) {
  final archive = Archive();
  for (final MapEntry(:key, :value) in files.entries) {
    archive.addFile(ArchiveFile(key, value.length, value));
  }
  return ZipEncoder().encodeBytes(archive);
}

const _enex = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE en-export SYSTEM "http://xml.evernote.com/pub/evernote-export4.dtd">
<en-export export-date="20261122T101500Z" application="Evernote" version="10">
  <note>
    <title>Trip &amp; plans</title>
    <created>20231122T101500Z</created>
    <updated>20231123T080000Z</updated>
    <tag>Travel</tag>
    <tag>2023</tag>
    <content><![CDATA[<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd">
<en-note><div>Flight at <b>9</b>&nbsp;am</div><div><br/></div><ul><li>Passport</li><li>Tickets</li></ul><div><a href="https://example.com">Hotel</a></div><en-media hash="abc" type="image/png"/></en-note>]]></content>
    <resource>
      <data encoding="base64">iVBORw0KGgo=</data>
      <mime>image/png</mime>
      <resource-attributes><file-name>map.png</file-name></resource-attributes>
    </resource>
    <resource>
      <data encoding="base64">
        JVBERg==
      </data>
      <mime>application/pdf</mime>
    </resource>
  </note>
  <note>
    <title>Shopping</title>
    <content><![CDATA[<en-note><div><en-todo checked="true"/>Milk</div><div><en-todo checked="false"/>Bread</div></en-note>]]></content>
  </note>
</en-export>''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HTML to text', () {
    test('paragraphs, lists, links, to-dos and entities', () {
      expect(
        htmlToText(
          '<h2>Title</h2><p>One&amp;two<br>three</p><ol><li>a</li><li>b</li></ol>'
          '<p><a href="https://x.org">X</a> <a href="https://y.org">https://y.org</a></p>'
          '<ul><li><input type="checkbox" checked> done</li><li><input type="checkbox"> open</li></ul>',
        ),
        '## Title\n\nOne&two\nthree\n\n- a\n- b\n\n[X](https://x.org) https://y.org\n\n- [x] done\n- [ ] open',
      );
    });

    test('a list of to-dos becomes a checklist', () {
      expect(checklistOf('[x] Milk\n[ ] Bread')!.map((i) => (i.text, i.checked)), [
        ('Milk', true),
        ('Bread', false),
      ]);
      expect(checklistOf('Milk\n[ ] Bread'), isNull);
    });
  });

  group('Evernote', () {
    test('notes, tags, dates, attachments and to-dos', () {
      final notes = const EvernoteParser().parse(_utf8(_enex))!;
      expect(notes, hasLength(2));
      final trip = notes.first;
      expect(trip.title, 'Trip & plans');
      expect(trip.body, 'Flight at 9 am\n\n- Passport\n- Tickets\n\n[Hotel](https://example.com)');
      expect(trip.tags, ['Travel', '2023']);
      expect(trip.createdAt, DateTime.utc(2023, 11, 22, 10, 15));
      expect(trip.files.map((f) => (f.name, f.mimeType, f.isImage)), [
        ('map.png', 'image/png', true),
        ('Attachment 2', 'application/pdf', false),
      ]);
      expect(trip.files.last.bytes, utf8.encode('%PDF'));
      final shopping = notes.last;
      expect(shopping.checklist!.map((i) => (i.text, i.checked)), [
        ('Milk', true),
        ('Bread', false),
      ]);
    });

    test('not an Evernote file', () {
      expect(const EvernoteParser().parse(_utf8('<html></html>')), isNull);
      expect(const EvernoteParser().parse(_utf8('not xml')), isNull);
    });
  });

  group('Standard Notes', () {
    test('notes with tags, pins, archive, trash; encrypted ones counted', () {
      final backup = {
        'version': '004',
        'items': [
          {
            'uuid': 'n1',
            'content_type': 'Note',
            'created_at': '2024-05-01T08:00:00.000Z',
            'content': {
              'title': 'Ideas',
              'text': 'Write more',
              'references': [],
              'appData': {
                'org.standardnotes.sn': {'pinned': true},
              },
            },
          },
          {
            'uuid': 'n2',
            'content_type': 'Note',
            'content': {
              'title': 'Old',
              'text': 'x',
              'appData': {
                'org.standardnotes.sn': {'archived': true},
              },
            },
          },
          {
            'uuid': 'n3',
            'content_type': 'Note',
            'content': {'title': 'Gone', 'text': 'y', 'trashed': true},
          },
          {'uuid': 'n4', 'content_type': 'Note', 'content': '004:abc:def'},
          {
            'uuid': 'n5',
            'content_type': 'Note',
            'content': {
              'title': 'Super',
              'noteType': 'super',
              'text': jsonEncode({
                'root': {
                  'type': 'root',
                  'children': [
                    {
                      'type': 'heading',
                      'tag': 'h1',
                      'children': [
                        {'type': 'text', 'text': 'Plan'},
                      ],
                    },
                    {
                      'type': 'list',
                      'children': [
                        {
                          'type': 'listitem',
                          'checked': true,
                          'children': [
                            {'type': 'text', 'text': 'Book'},
                          ],
                        },
                        {
                          'type': 'listitem',
                          'checked': false,
                          'children': [
                            {'type': 'text', 'text': 'Pack'},
                          ],
                        },
                      ],
                    },
                  ],
                },
              }),
            },
          },
          {
            'uuid': 't1',
            'content_type': 'Tag',
            'content': {
              'title': 'Work',
              'references': [
                {'uuid': 'n1', 'content_type': 'Note'},
              ],
            },
          },
        ],
      };
      final result = const StandardNotesParser().parse(_utf8(jsonEncode(backup)))!;
      expect(result.encrypted, 1);
      expect(result.notes.map((n) => n.title), ['Ideas', 'Old', 'Gone', 'Super']);
      final ideas = result.notes.first;
      expect(ideas.pinned, isTrue);
      expect(ideas.tags, ['Work']);
      expect(ideas.createdAt, DateTime.utc(2024, 5, 1, 8));
      expect(result.notes[1].archived, isTrue);
      expect(result.notes[2].trashed, isTrue);
      expect(result.notes[3].body, '# Plan\n- [x] Book\n- [ ] Pack');
    });

    test('other JSON is not a backup', () {
      expect(const StandardNotesParser().parse(_utf8('{"a": 1}')), isNull);
      expect(const StandardNotesParser().parse(_utf8('[1]')), isNull);
    });
  });

  group('Markdown folder', () {
    test("Notes' own Markdown export comes back the same", () async {
      final now = DateTime.utc(2026, 11, 22, 9);
      final exported = await MarkdownFolderExport.build(
        [
          Note(
            id: '1',
            notebookId: 'nb',
            title: 'Trip: Eilat',
            body: 'See [[Packing]]',
            createdAt: now,
            updatedAt: now,
            tagIds: const ['t'],
            pinned: true,
          ),
        ],
        notebookNames: {'nb': 'Travel'},
        tagNames: {'t': 'Holiday'},
      );
      final batch = parseOtherAppsFiles({'export.zip': exported.zip});
      final note = batch.notes.single;
      expect(note.title, 'Trip: Eilat');
      expect(note.body, 'See [[Packing]]');
      expect(note.notebook, 'Travel');
      expect(note.tags, ['Holiday']);
      expect(note.createdAt, now);
      expect(note.pinned, isTrue);
    });

    test('Obsidian-style vault: folders, headings, linked pictures', () {
      final notes = const MarkdownFolderParser().parse({
        'Vault/Recipes/Pancakes.md': _utf8(
          '# Best pancakes\n\nMix it.\n\n![[pan.jpg]]\n\n![photo](../assets/plate%201.png)\n\n'
          '[site](https://example.com)',
        ),
        'Vault/Inbox.md': _utf8(
          '---\ntags:\n  - "#todo"\n  - home\ncreated: 2025-01-02\n---\n- [ ] Call\n- [x] Pay',
        ),
        'Vault/Recipes/pan.jpg': [1],
        'Vault/assets/plate 1.png': [2],
      });
      final inbox = notes.firstWhere((n) => n.title == 'Inbox');
      expect(inbox.notebook, isNull);
      expect(inbox.tags, ['todo', 'home']);
      expect(inbox.createdAt, DateTime.utc(2025, 1, 2));
      expect(inbox.checklist!.map((i) => i.checked), [false, true]);
      final pancakes = notes.firstWhere((n) => n.title == 'Best pancakes');
      expect(pancakes.notebook, 'Recipes');
      expect(pancakes.body, 'Mix it.\n\n[site](https://example.com)');
      expect(pancakes.files.map((f) => (f.name, f.mimeType)), [
        ('pan.jpg', 'image/jpeg'),
        ('plate 1.png', 'image/png'),
      ]);
    });

    test("Apple's iCloud Notes copy: a folder per note, with its files", () {
      final notes = parseOtherAppsFiles({
        'icloud.zip': _zip({
          'iCloud Notes/Notes/Groceries/Groceries.txt': _utf8('Groceries\nEggs\nחלב'),
          'iCloud Notes/Notes/Groceries/receipt.pdf': [3],
          'iCloud Notes/Work/Plan/Plan.html': _utf8(
            '<html><body><div>Q1</div><div>Q2</div></body></html>',
          ),
          '__MACOSX/iCloud Notes/._Plan.html': [0],
        }),
      }).notes;
      expect(notes, hasLength(2));
      final groceries = notes.firstWhere((n) => n.title == 'Groceries');
      expect(groceries.body, 'Eggs\nחלב');
      expect(groceries.notebook, 'Notes');
      expect(groceries.files.single.name, 'receipt.pdf');
      final plan = notes.firstWhere((n) => n.title == 'Plan');
      expect(plan.notebook, 'Work');
      expect(plan.body, 'Q1\nQ2');
    });

    test('a single Apple note keeps the files in its own folder', () {
      final note = parseOtherAppsFiles({
        'icloud.zip': _zip({
          'iCloud Notes/Notes/Groceries/Groceries.txt': _utf8('Groceries\nEggs'),
          'iCloud Notes/Notes/Groceries/receipt.pdf': [3],
        }),
      }).notes.single;
      expect(note.title, 'Groceries');
      expect(note.files.single.name, 'receipt.pdf');
    });

    test("text, HTML and JSON files attached in Notes' export stay attachments", () async {
      final now = DateTime.utc(2026, 11, 22, 9);
      final key = Uint8List(32);
      final ref = ZtAttachmentRef(id: 'f1', key: key, name: 'instructions.txt', mimeType: 'text/plain', size: 5);
      final data = ZtAttachmentRef(id: 'f2', key: key, name: 'data.json', mimeType: 'application/json', size: 8);
      final exported = await MarkdownFolderExport.build(
        [
          Note(
            id: '1',
            notebookId: null,
            title: 'Setup',
            body: 'Read the files',
            createdAt: now,
            updatedAt: now,
            files: [ref, data],
          ),
        ],
        readFile: (file) async => utf8.encode(file.id == 'f1' ? 'steps' : '{"a": 1}'),
      );
      final note = parseOtherAppsFiles({'export.zip': exported.zip}).notes.single;
      expect(note.title, 'Setup');
      expect(note.files.map((f) => (f.name, utf8.decode(f.bytes))), [
        ('instructions.txt', 'steps'),
        ('data.json', '{"a": 1}'),
      ]);
    });

    test('front matter with quotes and inline lists', () {
      final (:fields, :body) = MarkdownFolderParser.splitFrontMatter(
        '---\ntitle: "A \\"quoted\\" title"\ntags: [one, "two, three"]\narchived: true\n---\nText',
      );
      expect(fields['title'], 'A "quoted" title');
      expect(fields['tags'], ['one', 'two, three']);
      expect(fields['archived'], 'true');
      expect(body, 'Text');
    });
  });

  group('importer', () {
    late Device phone;

    setUp(() async {
      phone = Device('phone', FakeSyncBackend());
      await phone.unlock();
    });

    tearDown(() => phone.container.dispose());

    test('notebooks, tags, pictures and files; a second run adds nothing', () async {
      final batch = parseOtherAppsFiles({
        'Travel.enex': _utf8(_enex),
        'Work.enex': _utf8(_enex.replaceAll('Trip &amp; plans', 'Budget')),
      });
      final importer = OtherAppsImporter(
        notes: phone.repo,
        tags: phone.container.read(tagsRepositoryProvider)!,
        notebooks: phone.container.read(notebooksRepositoryProvider),
      );
      final progress = <int>[];
      final first = await importer.run(batch.notes, onProgress: (done, _) => progress.add(done));
      // The same Shopping note in both exports comes in once.
      expect(first.imported, 3);
      expect(first.skippedDuplicates, 1);
      expect(first.filesNotAdded, 0);
      expect(progress.last, 4);

      final notes = await phone.repo.fetchAll();
      final notebooks = await phone.container.read(notebooksRepositoryProvider)!.fetchAll();
      expect(notebooks.map((n) => n.name), ['Travel', 'Work']);
      final tags = await phone.container.read(tagsRepositoryProvider)!.fetchAll();
      expect(tags.map((t) => t.name), unorderedEquals(['Travel', '2023']));
      final trip = notes.firstWhere((n) => n.title == 'Trip & plans');
      expect(trip.notebookId, notebooks.first.id);
      expect(trip.images.single.name, 'map.png');
      expect(trip.files.single.mimeType, 'application/pdf');
      expect(await phone.repo.readImage(trip.files.single), utf8.encode('%PDF'));
      expect(trip.createdAt, DateTime.utc(2023, 11, 22, 10, 15));
      final shopping = notes.firstWhere(
        (n) => n.title == 'Shopping' && n.notebookId == notebooks.first.id,
      );
      expect(shopping.isChecklist, isTrue);
      expect(shopping.body, '- [ ] Bread\n- [x] Milk');

      final again = await importer.run(parseOtherAppsFiles({'Travel.enex': _utf8(_enex)}).notes);
      expect(again.imported, 0);
      expect(again.skippedDuplicates, 2);
      expect(await phone.repo.fetchAll(), hasLength(3));
    });

    test('a file over 20 MB is counted, the note still comes in', () async {
      final importer = OtherAppsImporter(
        notes: phone.repo,
        tags: phone.container.read(tagsRepositoryProvider)!,
        notebooks: null,
      );
      final result = await importer.run([
        ImportedNote(
          title: 'Video',
          body: 'big',
          files: [
            ImportedFile(
              name: 'v.mp4',
              mimeType: 'video/mp4',
              bytes: Uint8List(20 * 1000 * 1000 + 1),
            ),
          ],
        ),
        const ImportedNote(title: 'Bin', body: 'x', trashed: true),
      ]);
      expect(result.imported, 1);
      expect(result.filesNotAdded, 1);
      expect(result.skippedTrashed, 1);
      expect((await phone.repo.fetchAll()).single.files, isEmpty);
    });
  });
}
