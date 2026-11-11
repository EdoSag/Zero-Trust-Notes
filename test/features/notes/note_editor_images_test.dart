import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';
import 'package:zerotrust_notes/src/features/images/note_image_picker.dart';
import 'package:zerotrust_notes/src/features/images/note_image_views.dart';
import 'package:zerotrust_notes/src/features/notes/application/notes_providers.dart';
import 'package:zerotrust_notes/src/features/notes/presentation/note_editor_page.dart';
import 'package:zerotrust_notes/src/features/sharing/note_sharing.dart';
import 'package:zerotrust_notes/src/features/widgets/domain/pending_widget_action.dart';

import '../../support/fake_sync_backend.dart';
import '../../support/notes_device.dart';
import 'notes_list_page_test.dart' show finish, settle;

/// A 1x1 PNG.
final pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

class FakePicker implements NoteImagePicker {
  final calls = <NoteImageSource>[];

  @override
  Future<List<PickedImage>> pick(NoteImageSource source) async {
    calls.add(source);
    return [
      PickedImage(bytes: pixel, mimeType: 'image/png', name: 'one.png'),
      PickedImage(bytes: pixel, mimeType: 'image/png', name: 'two.png'),
    ];
  }
}

void main() {
  const timeout = Timeout(Duration(seconds: 60));
  late Device phone;

  Future<void> pumpEditor(
    WidgetTester tester,
    Widget editor, {
    List<Override> overrides = const [],
  }) async {
    phone = Device('phone', FakeSyncBackend(), overrides: overrides);
    unawaited(phone.unlock());
    for (var i = 0; i < 50 && phone.container.read(notesRepositoryProvider) == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: phone.container,
        child: MaterialApp(localizationsDelegates: const [AppL10n.delegate, ...ZtLanguages.delegates], home: editor),
      ),
    );
    await settle(tester);
  }

  Future<T> real<T>(WidgetTester tester, Future<T> Function() body) async =>
      (await tester.runAsync(body)) as T;

  testWidgets('Add image puts encrypted images in the note and shows them', timeout: timeout, (
    tester,
  ) async {
    final picker = FakePicker();
    await pumpEditor(
      tester,
      const NoteEditorPage(),
      overrides: [noteImagePickerProvider.overrideWithValue(picker)],
    );

    await tester.enterText(find.byKey(const Key('note_title_field')), 'Receipts');
    await tester.tap(find.byTooltip('More options'));
    await settle(tester);
    await tester.tap(find.text('Add image'));
    await settle(tester);

    expect(picker.calls, [NoteImageSource.gallery]);
    expect(find.byType(NoteImageStrip), findsOneWidget);
    expect(find.bySemanticsLabel('Image 2 of 2'), findsOneWidget);

    final note = (await real(tester, phone.repo.fetchAll)).single;
    expect(note.title, 'Receipts');
    expect(note.images.map((i) => i.name), ['one.png', 'two.png']);
    expect(await real(tester, () => phone.repo.readImage(note.images.first)), pixel);
    await finish(tester, phone);
  });

  testWidgets('removing an image from the viewer takes it out of the note', timeout: timeout, (
    tester,
  ) async {
    await pumpEditor(
      tester,
      const NoteEditorPage(),
      overrides: [noteImagePickerProvider.overrideWithValue(FakePicker())],
    );
    await tester.tap(find.byTooltip('More options'));
    await settle(tester);
    await tester.tap(find.text('Add image'));
    await settle(tester);

    await tester.tap(find.bySemanticsLabel('Image 1 of 2'));
    await settle(tester);
    expect(find.text('1 of 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove image'));
    await settle(tester);
    await tester.tap(find.text('Remove'));
    await settle(tester);
    expect(find.text('Image'), findsOneWidget, reason: 'one image left');

    final note = (await real(tester, phone.repo.fetchAll)).single;
    expect(note.images.map((i) => i.name), ['two.png']);
    await finish(tester, phone);
  });

  testWidgets('text and images shared from another app become a new note', timeout: timeout, (
    tester,
  ) async {
    final dir = (await real(tester, () => Directory.systemTemp.createTemp('shared_in')));
    final file = File('${dir.path}/photo');
    await real(tester, () => file.writeAsBytes(pixel));

    await pumpEditor(
      tester,
      NoteEditorPage(
        shared: SharedContent(
          text: 'https://example.com/recipe',
          subject: 'Pancakes',
          images: [SharedImageFile(path: file.path, mimeType: 'image/png', name: 'p.png')],
          skipped: 1,
        ),
      ),
    );

    expect(find.text('Pancakes'), findsOneWidget);
    expect(find.byType(NoteImageStrip), findsOneWidget);
    expect(find.textContaining('One shared item couldn\'t be added'), findsOneWidget);

    final note = (await real(tester, phone.repo.fetchAll)).single;
    expect(note.title, 'Pancakes');
    expect(note.body, 'https://example.com/recipe');
    expect(note.images.single.name, 'p.png');
    expect(await real(tester, file.exists), isFalse, reason: 'the plain copy is deleted');
    expect(await real(tester, dir.exists), isFalse, reason: 'and its share folder');
    await finish(tester, phone);
  });

  testWidgets('Send hands the note to the share sheet as text', timeout: timeout, (tester) async {
    final sent = <ShareParams>[];
    await pumpEditor(
      tester,
      const NoteEditorPage(),
      overrides: [shareSheetProvider.overrideWithValue((params) async => sent.add(params))],
    );
    await tester.enterText(find.byKey(const Key('note_title_field')), 'Trip');
    await tester.enterText(find.byKey(const Key('note_body_field')), 'passport');
    await tester.tap(find.byTooltip('More options'));
    await settle(tester);
    await tester.tap(find.text('Send'));
    await settle(tester);

    expect(sent, hasLength(1));
    expect(sent.single.text, 'Trip\n\npassport');
    expect(sent.single.subject, 'Trip');
    expect(sent.single.files, isNull);
    await finish(tester, phone);
  });
}
