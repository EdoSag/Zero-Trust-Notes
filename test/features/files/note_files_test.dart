import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';
import 'package:zerotrust_notes/src/features/export/application/markdown_folder_export.dart';
import 'package:zerotrust_notes/src/features/files/note_file_picker.dart';
import 'package:zerotrust_notes/src/features/files/pdf_viewer_page.dart';
import 'package:zerotrust_notes/src/features/notes/application/notes_providers.dart';
import 'package:zerotrust_notes/src/features/notes/domain/note.dart';
import 'package:zerotrust_notes/src/features/notes/presentation/note_editor_page.dart';

import '../../support/fake_sync_backend.dart';
import '../../support/notes_device.dart';
import '../notes/notes_list_page_test.dart' show finish, settle;

ZtAttachmentRef _ref(String id, {String? name, String? mimeType, int size = 3}) =>
    ZtAttachmentRef(id: id * 32, key: Uint8List(32), size: size, name: name, mimeType: mimeType);

Note _note(
  String id, {
  String title = '',
  String body = '',
  String? notebookId,
  List<String> tagIds = const [],
  List<ZtAttachmentRef> images = const [],
  List<ZtAttachmentRef> files = const [],
}) => Note(
  id: id,
  notebookId: notebookId,
  title: title,
  body: body,
  createdAt: DateTime.utc(2026, 11, 22, 9),
  updatedAt: DateTime.utc(2026, 11, 22, 10),
  tagIds: tagIds,
  images: images,
  files: files,
);

class FakePdf implements PdfPageSource {
  Uint8List? opened;
  bool closed = false;
  final pages = <int>[];

  @override
  Future<int> open(Uint8List pdf) async {
    opened = pdf;
    return 2;
  }

  @override
  Future<Uint8List> page(int index, {required int width}) async {
    pages.add(index);
    return _png;
  }

  @override
  Future<void> close() async => closed = true;
}

// A 1x1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  const timeout = Timeout(Duration(seconds: 60));

  testWidgets('a PDF closed while it still loads leaves no open copy', (tester) async {
    final pdf = FakePdf();
    final load = Completer<Uint8List>();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppL10n.delegate, ...ZtLanguages.delegates],
        home: PdfViewerPage(title: 'doc.pdf', load: () => load.future, source: pdf),
      ),
    );
    await tester.pump();
    expect(find.text('doc.pdf'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(pdf.closed, isTrue);
    load.complete(Uint8List.fromList([1, 2, 3]));
    await tester.pump();
    expect(pdf.opened, isNull, reason: 'nothing is written once the viewer is gone');
  });

  group('note files', () {
    test('kept in the note JSON, counted as in use; older notes have none', () {
      final pdf = _ref('a', name: 'Lease.pdf', mimeType: 'application/pdf');
      final note = _note('n', files: [pdf]);
      final json = note.toItemJson();
      expect(json['files'], isA<List<Object?>>());
      final back = Note.fromItem(LocalItem(itemId: 'n', updatedAt: DateTime.utc(2026), json: json));
      expect(back.files.single.name, 'Lease.pdf');
      expect(back.attachments.map((a) => a.id), [pdf.id]);
      expect(back.extra, isEmpty);

      final old = Note.fromItem(
        LocalItem(
          itemId: 'o',
          updatedAt: DateTime.utc(2026),
          json: {'title': 'Old', 'body': 'x', 'createdAt': '2026-01-01T00:00:00Z'},
        ),
      );
      expect(old.files, isEmpty);
      expect(old.toItemJson().containsKey('files'), isFalse);
    });

    test('file types from names', () {
      expect(fileMimeType('Lease.PDF'), 'application/pdf');
      expect(fileMimeType('notes.md'), 'text/markdown');
      expect(fileMimeType('photo.jpeg'), 'image/jpeg');
      expect(fileMimeType('mystery'), isNull);
    });
  });

  group('Markdown folder export', () {
    Map<String, String> unzip(Uint8List zip) => {
      for (final file in ZipDecoder().decodeBytes(zip).files)
        if (file.isFile) file.name: utf8.decode(file.content, allowMalformed: true),
    };

    test('one file per note, notebook folders, front matter, attachments linked', () async {
      final photo = _ref('p', name: 'Beach.jpg', mimeType: 'image/jpeg');
      final pdf = _ref('f', name: 'Lease 2026.pdf', mimeType: 'application/pdf');
      final gone = _ref('g', name: 'Elsewhere.pdf', mimeType: 'application/pdf');
      final result = await MarkdownFolderExport.build(
        [
          _note(
            '1',
            title: 'Trip: "Eilat"',
            body: 'See [[Packing]]',
            notebookId: 'nb',
            tagIds: ['t'],
          ),
          _note('2', title: 'Packing', body: '- [ ] Hat', images: [photo], files: [pdf, gone]),
          _note('3', title: 'packing', body: 'Same name'),
          _note('4', title: 'קניות', body: 'חלב'),
          _note('5', body: 'No title'),
        ],
        notebookNames: {'nb': 'Travel'},
        tagNames: {'t': 'Holiday'},
        readFile: (file) async {
          if (file.id == gone.id) throw StateError('not here');
          return Uint8List.fromList(utf8.encode('bytes of ${file.name}'));
        },
      );
      expect(result.missing, 1);
      final files = unzip(result.zip);
      expect(
        files.keys,
        unorderedEquals([
          'Travel/Trip Eilat.md',
          'Packing.md',
          'packing (2).md',
          'קניות.md',
          'Untitled.md',
          '_attachments/Beach.jpg',
          '_attachments/Lease 2026.pdf',
        ]),
      );
      final trip = files['Travel/Trip Eilat.md']!;
      expect(trip, startsWith('---\ntitle: "Trip: \\"Eilat\\""\n'));
      expect(trip, contains('notebook: "Travel"\n'));
      expect(trip, contains('tags: ["Holiday"]\n'));
      expect(trip, contains('---\n\nSee [[Packing]]\n'));
      final packing = files['Packing.md']!;
      expect(packing, contains('![Beach.jpg](_attachments/Beach.jpg)'));
      expect(packing, contains('[Lease 2026.pdf](_attachments/Lease%202026.pdf)'));
      expect(packing, isNot(contains('Elsewhere')));
      expect(files['_attachments/Lease 2026.pdf'], 'bytes of Lease 2026.pdf');
      expect(files['קניות.md'], contains('חלב'));
    });

    test('safe file names', () {
      expect(MarkdownFolderExport.safeFileName('a/b\\c:d', fallback: 'x'), 'a b c d');
      expect(MarkdownFolderExport.safeFileName('..hidden', fallback: 'x'), 'hidden');
      expect(MarkdownFolderExport.safeFileName('   ', fallback: 'x'), 'x');
      expect(MarkdownFolderExport.safeFileName('y' * 200, fallback: 'x'), hasLength(80));
    });
  });

  group('editor', () {
    late Device phone;

    Future<void> pumpEditor(WidgetTester tester, {List<Override> overrides = const []}) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      phone = Device('phone', FakeSyncBackend(), overrides: overrides);
      unawaited(phone.unlock());
      for (var i = 0; i < 50 && phone.container.read(notesRepositoryProvider) == null; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: phone.container,
          child: MaterialApp(
            theme: ZtTheme.light(),
            localizationsDelegates: const [AppL10n.delegate, ...ZtLanguages.delegates],
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: (_) => const NoteEditorPage())),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('open'));
      await settle(tester);
    }

    Future<void> menu(WidgetTester tester, String item) async {
      await tester.tap(find.byTooltip('More options'));
      await settle(tester);
      await tester.tap(find.text(item));
      await settle(tester);
    }

    PickedNoteFile picked(String name, List<int> bytes, {int? size}) =>
        (name: name, size: size ?? bytes.length, read: () async => Uint8List.fromList(bytes));

    testWidgets(
      'attach a PDF and a big file: the PDF opens in Notes, the big one is refused',
      timeout: timeout,
      (tester) async {
        final pdf = FakePdf();
        await pumpEditor(
          tester,
          overrides: [
            noteFilePickerProvider.overrideWithValue(
              () async => [
                picked('Lease.pdf', [37, 80, 68, 70]),
                picked('Movie.mp4', [1], size: 30 * 1000 * 1000),
              ],
            ),
            pdfPageSourceProvider.overrideWithValue(() => pdf),
          ],
        );
        await tester.enterText(find.byKey(const Key('note_body_field')), 'Flat');
        await menu(tester, 'Attach file');
        expect(find.textContaining('over 20 MB'), findsOneWidget);

        var note = (await tester.runAsync(() => phone.repo.fetchAll()))!.single;
        expect(note.files.single.name, 'Lease.pdf');
        expect(note.files.single.mimeType, 'application/pdf');
        expect(note.images, isEmpty);
        final chip = find.byKey(ValueKey('note_file_${note.files.single.id}'));
        expect(chip, findsOneWidget);
        // The chip sits above the text, on screen.
        expect(
          tester.getRect(chip).bottom,
          lessThan(tester.getRect(find.byKey(const Key('note_body_field'))).bottom),
        );

        await tester.tap(chip);
        await settle(tester);
        expect(find.byKey(const Key('pdf_page_0')), findsOneWidget);
        expect(pdf.opened, [37, 80, 68, 70]);
        expect(find.text('Lease.pdf'), findsWidgets);

        await tester.tap(find.byKey(const Key('pdf_remove')));
        await settle(tester);
        expect(pdf.closed, isTrue);
        expect(chip, findsNothing);
        note = (await tester.runAsync(() => phone.repo.fetchAll()))!.single;
        expect(note.files, isEmpty);
        await finish(tester, phone);
      },
    );

    testWidgets('a picture chosen as a file goes with the note\'s images', timeout: timeout, (
      tester,
    ) async {
      await pumpEditor(
        tester,
        overrides: [
          noteFilePickerProvider.overrideWithValue(() async => [picked('Scan.png', _png)]),
        ],
      );
      await menu(tester, 'Attach file');
      final note = (await tester.runAsync(() => phone.repo.fetchAll()))!.single;
      expect(note.images.single.name, 'Scan.png');
      expect(note.files, isEmpty);
      await finish(tester, phone);
    });
  });
}
