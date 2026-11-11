import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';
import 'package:zerotrust_notes/src/features/drawing/drawing.dart';
import 'package:zerotrust_notes/src/features/image_text/image_text_reader.dart';
import 'package:zerotrust_notes/src/features/images/note_image_picker.dart';
import 'package:zerotrust_notes/src/features/notes/application/notes_providers.dart';
import 'package:zerotrust_notes/src/features/notes/domain/note.dart';
import 'package:zerotrust_notes/src/features/notes/presentation/note_editor_page.dart';

import '../../support/fake_sync_backend.dart';
import '../../support/notes_device.dart';
import 'note_editor_images_test.dart' show FakePicker, pixel;
import 'notes_list_page_test.dart' show finish, settle;

class FakeReader implements ImageTextReader {
  FakeReader(this.byLanguage);
  final Map<String, String> byLanguage;
  final asked = <String>[];
  final seen = <Uint8List>[];

  @override
  bool get supported => true;

  @override
  Future<String> read(Uint8List bytes, {required String languages}) async {
    asked.add(languages);
    seen.add(bytes);
    return tidyImageText(byLanguage[languages] ?? '');
  }
}

void main() {
  const timeout = Timeout(Duration(seconds: 60));
  late Device phone;

  group('image text', () {
    test('tidy keeps paragraphs, drops noise', () {
      expect(tidyImageText('  Milk  \n\n\n\nBread\r\n  \n'), '  Milk\n\nBread');
      expect(tidyImageText('\n\n'), '');
    });

    test('languages: the app language goes first when reading both', () {
      expect(ImageTextLanguage.both.tesseract(hebrewFirst: true), 'heb+eng');
      expect(ImageTextLanguage.both.tesseract(hebrewFirst: false), 'eng+heb');
      expect(ImageTextLanguage.hebrew.tesseract(hebrewFirst: false), 'heb');
    });
  });

  group('drawing', () {
    const stroke = Stroke(
      points: [Offset(10, 10), Offset(50, 10), Offset(50.37, 80.04)],
      color: Color(0xFFD32F2F),
      width: 4,
      pressures: [0.2, 0.5, 1],
    );

    test('strokes survive encode and decode', () {
      const drawing = Drawing(
        size: Size(360, 640),
        strokes: [
          stroke,
          Stroke(points: [Offset(1, 2)], color: Color(0xFF000000), width: 8, highlighter: true),
        ],
      );
      final back = Drawing.decode(drawing.encode())!;
      expect(back.size, drawing.size);
      expect(back.strokes, hasLength(2));
      expect(back.strokes.first.points.last.dx, closeTo(50.4, 0.01));
      expect(back.strokes.first.pressures, [0.2, 0.5, 1]);
      expect(back.strokes.first.color, stroke.color);
      expect(back.strokes.last.highlighter, isTrue);
      expect(Drawing.decode(Uint8List.fromList([1, 2, 3])), isNull);
    });

    test('the eraser finds the line it touches', () {
      expect(stroke.hits(const Offset(30, 12), 4), isTrue);
      expect(stroke.hits(const Offset(30, 40), 4), isFalse);
    });

    test('note JSON keeps drawings, and their strokes count as in use', () {
      final picture = ZtAttachmentRef(id: 'a' * 32, key: Uint8List(32), size: 1);
      final strokes = ZtAttachmentRef(id: 'b' * 32, key: Uint8List(32), size: 1);
      final note = Note(
        id: 'n',
        notebookId: null,
        title: '',
        body: '',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        images: [picture],
        drawings: {picture.id: strokes},
      );
      final back = Note.fromItem(
        LocalItem(itemId: 'n', updatedAt: DateTime.utc(2026), json: note.toItemJson()),
      );
      expect(back.drawings[picture.id], strokes);
      expect(back.attachments.map((a) => a.id), [picture.id, strokes.id]);
      expect(back.extra, isEmpty);
    });
  });

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

  /// The button with [key] is inside the screen and can be tapped.
  void expectTappable(WidgetTester tester, Key key) {
    final rect = tester.getRect(find.byKey(key));
    final screen = Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(rect.isFinite && rect.width > 0, isTrue, reason: '$key has no size');
    expect(screen.contains(rect.center), isTrue, reason: '$key is off screen at $rect');
    expect(find.byKey(key).hitTestable(), findsOneWidget);
  }

  testWidgets('text from a photo goes into the note, the photo does not', timeout: timeout, (
    tester,
  ) async {
    final reader = FakeReader({'eng+heb': 'Milk\nחלב', 'heb': 'חלב'});
    await pumpEditor(
      tester,
      overrides: [
        noteImagePickerProvider.overrideWithValue(FakePicker()),
        imageTextReaderProvider.overrideWithValue(reader),
      ],
    );
    await tester.enterText(find.byKey(const Key('note_body_field')), 'List:');
    await menu(tester, 'Text from a photo');
    expect(find.textContaining('never uploaded'), findsOneWidget);
    await tester.tap(find.text('Choose a photo'));
    await settle(tester);
    expect(find.text('Milk\nחלב'), findsOneWidget);
    expect(reader.seen.single, pixel);
    expectTappable(tester, const Key('image_text_add'));
    expectTappable(tester, const Key('image_text_copy'));

    // Hebrew only reads again.
    await tester.tap(find.text('Hebrew'));
    await settle(tester);
    expect(reader.asked, ['eng+heb', 'heb']);
    await tester.tap(find.byKey(const Key('image_text_add')));
    await settle(tester);

    await tester.pageBack();
    await settle(tester);
    final note = (await tester.runAsync(() => phone.repo.fetchAll()))!.single;
    expect(note.body, 'List:\n\nחלב');
    expect(note.images, isEmpty);
    await finish(tester, phone);
  });

  testWidgets('no text found says so, and Add stays off', timeout: timeout, (tester) async {
    await pumpEditor(
      tester,
      overrides: [
        noteImagePickerProvider.overrideWithValue(FakePicker()),
        imageTextReaderProvider.overrideWithValue(FakeReader({})),
      ],
    );
    await menu(tester, 'Text from a photo');
    await tester.tap(find.text('Choose a photo'));
    await settle(tester);
    expect(find.byKey(const Key('image_text_none')), findsOneWidget);
    final add = tester.widget<ButtonStyleButton>(find.byKey(const Key('image_text_add')));
    expect(add.onPressed, isNull);
    await finish(tester, phone);
  });

  testWidgets('draw with a stylus and save: picture and strokes in the note', timeout: timeout, (
    tester,
  ) async {
    await pumpEditor(tester);
    await menu(tester, 'Drawing');
    expect(find.text('New drawing'), findsOneWidget);
    final canvas = tester.getRect(find.byKey(const Key('drawing_canvas')));
    // The toolbar is below the canvas and on screen.
    expectTappable(tester, const Key('drawing_color_5'));
    expect(tester.getRect(find.byKey(const Key('drawing_color_5'))).top, greaterThan(canvas.top));

    final gesture = await tester.startGesture(canvas.center, kind: PointerDeviceKind.stylus);
    for (var i = 1; i <= 10; i++) {
      await gesture.moveBy(const Offset(8, 4));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('drawing_save')));
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await settle(tester);
    expect(find.text('New drawing'), findsNothing);
    await settle(tester);
    var note = (await tester.runAsync(() => phone.repo.fetchAll()))!.single;
    expect(note.images, hasLength(1));
    final first = note.images.single;
    expect(note.drawings.keys, [first.id]);
    final strokes = (await tester.runAsync(() => phone.repo.readImage(note.drawings[first.id]!)))!;
    final drawing = Drawing.decode(strokes)!;
    expect(drawing.strokes.single.points.length, greaterThan(5));
    expect(drawing.strokes.single.pressures, isNotNull, reason: 'drawn with a stylus');

    // Open it again from the image viewer, add a line, save: it replaces
    // the old picture in place and the old files are let go.
    await tester.tap(find.byKey(ValueKey('note_image_${first.id}')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('image_viewer_edit_drawing')));
    await settle(tester);
    expect(find.text('Edit drawing'), findsOneWidget);
    final area = tester.getRect(find.byKey(const Key('drawing_canvas')));
    final again = await tester.startGesture(area.topLeft + const Offset(20, 20));
    for (var i = 1; i <= 5; i++) {
      await again.moveBy(const Offset(10, 10));
      await tester.pump();
    }
    await again.up();
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('drawing_save')));
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await settle(tester);
    await tester.pageBack();
    await settle(tester);
    note = (await tester.runAsync(() => phone.repo.fetchAll()))!.single;
    expect(note.images, hasLength(1));
    expect(note.images.single.id, isNot(first.id));
    final edited = Drawing.decode(
      (await tester.runAsync(() => phone.repo.readImage(note.drawings[note.images.single.id]!)))!,
    )!;
    expect(edited.strokes, hasLength(2));
    final oldGone = await tester.runAsync(() async {
      try {
        await phone.repo.readImage(first);
        return false;
      } on AttachmentNotFound {
        return true;
      }
    });
    expect(oldGone, isTrue, reason: 'the old picture was deleted');
    await finish(tester, phone);
  });
}
