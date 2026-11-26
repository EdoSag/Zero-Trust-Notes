import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';
import 'package:zerotrust_notes/src/features/assist/note_assist.dart';
import 'package:zerotrust_notes/src/features/notes/application/notes_providers.dart';
import 'package:zerotrust_notes/src/features/notes/presentation/note_editor_page.dart';
import 'package:zt_assist/testing.dart';
import 'package:zt_assist/zt_assist.dart';

import '../../support/fake_sync_backend.dart';
import '../../support/notes_device.dart';
import '../notes/notes_list_page_test.dart' show finish, settle;

void main() {
  const timeout = Timeout(Duration(seconds: 60));
  late Device phone;

  test('a suggested title is tidied into a title', () {
    expect(tidyAssistTitle('Kitchen renovation plan'), 'Kitchen renovation plan');
    expect(tidyAssistTitle('\n **"Kitchen plan"** \nMore words'), 'Kitchen plan');
    expect(tidyAssistTitle('Title: Kitchen plan'), 'Kitchen plan');
    expect(tidyAssistTitle('# Kitchen plan'), 'Kitchen plan');
    expect(tidyAssistTitle('כותרת: ״שיפוץ המטבח״'), 'שיפוץ המטבח');
    expect(tidyAssistTitle('  \n '), '');
  });

  test('only answers in the text\'s own form can replace it', () {
    expect(
      [
        for (final action in NoteAssistAction.values)
          if (action.transforms) action,
      ],
      [NoteAssistAction.rewrite, NoteAssistAction.proofread, NoteAssistAction.translate],
    );
  });

  Future<void> pumpEditor(
    WidgetTester tester,
    ZtAssist assist, {
    Locale? locale,
    bool checklist = false,
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    phone = Device(
      'phone',
      FakeSyncBackend(),
      overrides: [ztAssistProvider.overrideWithValue(assist), ...overrides],
    );
    unawaited(phone.unlock());
    for (var i = 0; i < 50 && phone.container.read(notesRepositoryProvider) == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: phone.container,
        child: MaterialApp(
          // The suite's real theme: its buttons are as wide as they are
          // allowed to be, which breaks rows a plain theme lets through.
          theme: ZtTheme.light(),
          locale: locale,
          supportedLocales: AppL10n.supportedLocales,
          localizationsDelegates: const [AppL10n.delegate, ...ZtLanguages.delegates],
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => NoteEditorPage(startAsChecklist: checklist),
                ),
              ),
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

  Future<void> openAssist(WidgetTester tester, {String item = 'Ask ZT Assist'}) async {
    await tester.tap(find.byType(PopupMenuButton<String>));
    await settle(tester);
    await tester.tap(find.text(item));
    await settle(tester);
  }

  /// The button with [key] is inside the screen and can be tapped.
  void expectTappable(WidgetTester tester, Key key) {
    final rect = tester.getRect(find.byKey(key));
    final screen = Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(rect.isFinite && rect.width > 40, isTrue, reason: '$key has no size');
    expect(screen.contains(rect.center), isTrue, reason: '$key is off screen at $rect');
    expect(find.byKey(key).hitTestable(), findsOneWidget);
  }

  String bodyOf(WidgetTester tester) =>
      tester.widget<TextField>(find.byKey(const Key('note_body_field'))).controller!.text;

  testWidgets('without ZT Assist on the phone the menu does not offer it', timeout: timeout, (
    tester,
  ) async {
    await pumpEditor(tester, FakeZtAssist(state: ZtAssistAvailability.notInstalled));
    await tester.tap(find.byType(PopupMenuButton<String>));
    await settle(tester);
    expect(find.text('Ask ZT Assist'), findsNothing);
    expect(find.text('Colour'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await settle(tester);
    await finish(tester, phone);
  });

  testWidgets('a summary is written piece by piece and added to the note', timeout: timeout, (
    tester,
  ) async {
    final gate = Completer<void>();
    final assist = FakeZtAssist(
      answer: (_) => ['- Work starts', ' in January'],
      beforePiece: () => gate.future,
    );
    await pumpEditor(tester, assist);
    await tester.enterText(find.byKey(const Key('note_body_field')), 'Long kitchen notes');
    await openAssist(tester);

    expect(find.textContaining('not sent anywhere'), findsOneWidget);
    expect(find.byKey(const Key('assist_on_selection')), findsNothing);
    for (final action in NoteAssistAction.values) {
      expectTappable(tester, Key('assist_${action.name}'));
    }
    await tester.tap(find.byKey(const Key('assist_summarize')));
    await tester.pump();
    await tester.pump();

    // Waiting for the first piece: it says so and can be stopped.
    expect(find.byKey(const Key('assist_starting')), findsOneWidget);
    expectTappable(tester, const Key('assist_stop'));
    expect(assist.requests.single.task, ZtAssistTask.summarize);
    expect(assist.requests.single.text, 'Long kitchen notes');

    gate.complete();
    await settle(tester);
    expect(find.text('- Work starts in January'), findsOneWidget);
    expect(find.byKey(const Key('assist_stop')), findsNothing);
    // A summary is added, never put in the text's place.
    expect(find.byKey(const Key('assist_replace')), findsNothing);
    expectTappable(tester, const Key('assist_copy'));
    expectTappable(tester, const Key('assist_append'));
    // Side by side, each with room for its label.
    final copy = tester.getRect(find.byKey(const Key('assist_copy')));
    final add = tester.getRect(find.byKey(const Key('assist_append')));
    expect(copy.right, lessThanOrEqualTo(add.left));
    expect(copy.width, greaterThan(120));
    expect(add.width, greaterThan(120));

    await tester.tap(find.byKey(const Key('assist_append')));
    await settle(tester);
    expect(bodyOf(tester), 'Long kitchen notes\n\n- Work starts in January');

    await tester.pageBack();
    await settle(tester);
    final note = (await tester.runAsync(() => phone.repo.fetchAll()))!.single;
    expect(note.body, 'Long kitchen notes\n\n- Work starts in January');
    await finish(tester, phone);
  });

  testWidgets('selected text is rewritten in place, and Undo brings it back', timeout: timeout, (
    tester,
  ) async {
    final assist = FakeZtAssist(answer: (_) => ['we will meet', ' on Sunday']);
    await pumpEditor(tester, assist);
    const before = 'Hi Dana, lets meat on sunday ok? Thanks';
    await tester.enterText(find.byKey(const Key('note_body_field')), before);
    final field = tester.widget<TextField>(find.byKey(const Key('note_body_field')));
    field.controller!.selection = const TextSelection(baseOffset: 9, extentOffset: 28);
    await tester.pump();

    await openAssist(tester);
    expect(find.byKey(const Key('assist_on_selection')), findsOneWidget);
    await tester.tap(find.byKey(const Key('assist_rewrite')));
    await settle(tester);

    expect(assist.requests.single.task, ZtAssistTask.rewrite);
    expect(assist.requests.single.text, 'lets meat on sunday');
    expect(find.text('Replace the selected text'), findsOneWidget);
    expectTappable(tester, const Key('assist_replace'));
    expectTappable(tester, const Key('assist_append'));
    expectTappable(tester, const Key('assist_copy'));
    // The wide button sits under the row of two, not on top of it.
    expect(
      tester.getRect(find.byKey(const Key('assist_replace'))).top,
      greaterThanOrEqualTo(tester.getRect(find.byKey(const Key('assist_copy'))).bottom),
    );

    await tester.tap(find.byKey(const Key('assist_replace')));
    await settle(tester);
    expect(bodyOf(tester), 'Hi Dana, we will meet on Sunday ok? Thanks');
    expect(find.text('The text was replaced.'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(bodyOf(tester), before);
    await finish(tester, phone);
  });

  testWidgets('a suggested title becomes the title', timeout: timeout, (tester) async {
    final assist = FakeZtAssist(answer: (_) => ['**"Kitchen', ' plan"**']);
    await pumpEditor(tester, assist);
    await tester.enterText(find.byKey(const Key('note_body_field')), 'Cabinets, tiles, sink');
    await openAssist(tester);
    await tester.tap(find.byKey(const Key('assist_title')));
    await settle(tester);

    expectTappable(tester, const Key('assist_use_title'));
    expect(find.byKey(const Key('assist_append')), findsNothing);
    await tester.tap(find.byKey(const Key('assist_use_title')));
    await settle(tester);

    expect(
      tester.widget<TextField>(find.byKey(const Key('note_title_field'))).controller!.text,
      'Kitchen plan',
    );
    expect(bodyOf(tester), 'Cabinets, tiles, sink');
    await finish(tester, phone);
  });

  testWidgets('a text too long to rewrite whole cannot replace the note', timeout: timeout, (
    tester,
  ) async {
    final assist = FakeZtAssist(
      answer: (_) => ['Only the start, rewritten'],
      done: const ZtAssistDone(truncated: true),
    );
    await pumpEditor(tester, assist);
    await tester.enterText(find.byKey(const Key('note_body_field')), 'A very long note');
    await openAssist(tester);
    await tester.tap(find.byKey(const Key('assist_proofread')));
    await settle(tester);

    expect(find.textContaining('too long to do in one go'), findsOneWidget);
    final replace = tester.widget<FilledButton>(find.byKey(const Key('assist_replace')));
    expect(replace.onPressed, isNull);
    // The part that was done can still be added or copied.
    await tester.tap(find.byKey(const Key('assist_append')));
    await settle(tester);
    expect(bodyOf(tester), 'A very long note\n\nOnly the start, rewritten');
    await finish(tester, phone);
  });

  testWidgets(
    'Stop keeps what was written but does not let it replace the text',
    timeout: timeout,
    (tester) async {
      final gates = [Completer<void>(), Completer<void>()];
      var piece = 0;
      final assist = FakeZtAssist(
        answer: (_) => ['Half', ' of it'],
        beforePiece: () => gates[piece++].future,
      );
      await pumpEditor(tester, assist);
      await tester.enterText(find.byKey(const Key('note_body_field')), 'Some text');
      await openAssist(tester);
      await tester.tap(find.byKey(const Key('assist_translate')));
      await tester.pump();
      gates[0].complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('Half'), findsOneWidget);

      await tester.tap(find.byKey(const Key('assist_stop')));
      await settle(tester);
      gates[1].complete();
      await settle(tester);

      expect(assist.cancelled, 1);
      expect(find.text('Half'), findsOneWidget);
      expect(find.text('Stopped before the end.'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('assist_replace'))).onPressed,
        isNull,
      );

      // Back to the choices, and closing changes nothing.
      await tester.tap(find.byKey(const Key('assist_back')));
      await settle(tester);
      expect(find.byKey(const Key('assist_summarize')), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await settle(tester);
      expect(bodyOf(tester), 'Some text');
      await finish(tester, phone);
    },
  );

  testWidgets('a failure is said in words, and another try is one tap away', timeout: timeout, (
    tester,
  ) async {
    final assist = FakeZtAssist(answer: (_) => const [], error: ZtAssistError.noModel);
    await pumpEditor(tester, assist);
    await tester.enterText(find.byKey(const Key('note_body_field')), 'Some text');
    await openAssist(tester);
    await tester.tap(find.byKey(const Key('assist_summarize')));
    await settle(tester);

    expect(
      find.text('ZT Assist has no model yet. Open ZT Assist and download one.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('assist_copy')), findsNothing);
    expectTappable(tester, const Key('assist_back'));

    assist.error = null;
    assist.answer = (_) => ['Fine now'];
    await tester.tap(find.byKey(const Key('assist_back')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('assist_summarize')));
    await settle(tester);
    expect(find.text('Fine now'), findsOneWidget);
    expect(find.byKey(const Key('assist_error')), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await settle(tester);
    await finish(tester, phone);
  });

  testWidgets('an empty note has nothing to ask about', timeout: timeout, (tester) async {
    final assist = FakeZtAssist();
    await pumpEditor(tester, assist);
    await openAssist(tester);
    expect(find.text('There is no text in this note yet.'), findsOneWidget);
    expect(assist.requests, isEmpty);
    await finish(tester, phone);
  });

  testWidgets('a checklist can be summarized and titled, not rewritten', timeout: timeout, (
    tester,
  ) async {
    final assist = FakeZtAssist(answer: (_) => ['Shopping for the weekend']);
    await pumpEditor(tester, assist, checklist: true);
    await tester.tap(find.byKey(const Key('checklist_add_item')));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, 'Milk');
    await settle(tester);
    await openAssist(tester);

    expect(find.byKey(const Key('assist_summarize')), findsOneWidget);
    expect(find.byKey(const Key('assist_title')), findsOneWidget);
    expect(find.byKey(const Key('assist_rewrite')), findsNothing);
    expect(find.byKey(const Key('assist_proofread')), findsNothing);
    expect(find.byKey(const Key('assist_translate')), findsNothing);

    await tester.tap(find.byKey(const Key('assist_summarize')));
    await settle(tester);
    expect(assist.requests.single.text, contains('Milk'));
    // A summary is not a list item: it can be copied, not added.
    expectTappable(tester, const Key('assist_copy'));
    expect(find.byKey(const Key('assist_append')), findsNothing);
    expect(find.byKey(const Key('assist_replace')), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await settle(tester);
    await finish(tester, phone);
  });

  testWidgets('in Hebrew the sheet reads right to left and fits', timeout: timeout, (tester) async {
    final assist = FakeZtAssist(answer: (_) => ['נפגש ביום ראשון']);
    await pumpEditor(tester, assist, locale: const Locale('he'));
    await tester.enterText(find.byKey(const Key('note_body_field')), 'ניפגש ביום ראשון');
    await openAssist(tester, item: 'שאלה ל-ZT Assist');

    expect(find.text('שיפור הניסוח'), findsOneWidget);
    await tester.tap(find.byKey(const Key('assist_rewrite')));
    await settle(tester);

    expectTappable(tester, const Key('assist_copy'));
    expectTappable(tester, const Key('assist_append'));
    expectTappable(tester, const Key('assist_replace'));
    // Right to left: Copy is on the right of Add to note.
    expect(
      tester.getRect(find.byKey(const Key('assist_copy'))).left,
      greaterThanOrEqualTo(tester.getRect(find.byKey(const Key('assist_append'))).right),
    );
    expect(find.text('החלפת הטקסט של הפתק'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(5, 5));
    await settle(tester);
    await finish(tester, phone);
  });
}
