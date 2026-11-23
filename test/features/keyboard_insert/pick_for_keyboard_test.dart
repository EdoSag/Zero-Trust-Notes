import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart' show ZtLanguages, ZtTheme;
import 'package:zerotrust_notes/l10n/l10n.dart';
import 'package:zerotrust_notes/src/features/keyboard_insert/keyboard_pick_listener.dart';
import 'package:zerotrust_notes/src/features/keyboard_insert/pick_for_keyboard_page.dart';
import 'package:zerotrust_notes/src/features/notes/application/notes_providers.dart';
import 'package:zerotrust_notes/src/features/notes/domain/checklist_item.dart';
import 'package:zerotrust_notes/src/features/notes/domain/note.dart';

Note note(
  String id,
  String title,
  String body, {
  bool locked = false,
  bool archived = false,
  DateTime? trashedAt,
  List<ChecklistItem>? checklist,
}) => Note(
  id: id,
  notebookId: null,
  title: title,
  body: body,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  locked: locked,
  archived: archived,
  trashedAt: trashedAt,
  checklist: checklist,
);

void main() {
  final notes = [
    note('1', 'Wi-Fi', '## Home\n**Password:** tulip-42\n\n- guest: daisy-7'),
    note('2', 'Bank', 'IBAN IL00 1234', locked: true),
    note('3', '', 'Gate code 4411'),
    note('4', 'Old', 'archived text', archived: true),
    note('5', 'Gone', 'trashed text', trashedAt: DateTime.utc(2026)),
    note(
      '6',
      'Shopping',
      '',
      checklist: const [
        ChecklistItem(id: 'a', text: 'Milk'),
        ChecklistItem(id: 'b', text: ' '),
        ChecklistItem(id: 'c', text: 'Milk'),
      ],
    ),
    note('7', '', '   '),
  ];

  test('lines: title, then each line as plain text, no blanks or repeats', () {
    expect(pickLinesOf(notes[0]), ['Wi-Fi', 'Home', 'Password: tulip-42', 'guest: daisy-7']);
    expect(pickLinesOf(notes[5]), ['Shopping', 'Milk']);
    expect(pickLinesOf(notes[6]), isEmpty);
  });

  test('identifiers and passwords are typed exactly as written', () {
    expect(
      pickLinesOf(
        note(
          '8',
          'api_key_v2 *new*',
          'user: account_ab_cd\n- pass: a*b*c  __x__\n1. [docs](https://x.io) `tok_en`\n```\n  raw **kept**\n```',
        ),
      ),
      [
        'api_key_v2 *new*',
        'user: account_ab_cd',
        'pass: a*b*c  __x__',
        'docs tok_en',
        'raw **kept**',
      ],
    );
    expect(
      pickLinesOf(
        note('9', '', '', checklist: const [ChecklistItem(id: 'a', text: 'account_ab_cd  **x**')]),
      ),
      ['account_ab_cd  **x**'],
    );
  });

  test('locked, archived, trashed and empty notes are never offered', () {
    expect(pickableNotes(notes, '').map((n) => n.id), ['1', '3', '6']);
    expect(pickableNotes(notes, 'TULIP').map((n) => n.id), ['1']);
    // A locked note is not found by its text either.
    expect(pickableNotes(notes, 'iban'), isEmpty);
  });

  Future<String? Function()> open(WidgetTester tester) async {
    String? picked = 'unset';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [notesListProvider.overrideWithValue(AsyncData(notes))],
        child: MaterialApp(
          theme: ZtTheme.light(),
          localizationsDelegates: const [AppL10n.delegate, ...ZtLanguages.delegates],
          supportedLocales: ZtLanguages.supported,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    picked = await Navigator.of(
                      context,
                    ).push<String>(MaterialPageRoute(builder: (_) => const PickForKeyboardPage()));
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => picked;
  }

  testWidgets('tapping a note and then a line hands that line back', (tester) async {
    final picked = await open(tester);
    expect(find.text('Insert into ZT Keyboard'), findsOneWidget);
    expect(find.text('Bank'), findsNothing);
    expect(find.text('Old'), findsNothing);
    // The notes are listed under the search field, on screen.
    final search = tester.getBottomLeft(find.byType(TextField)).dy;
    final wifi = tester.getTopLeft(find.text('Wi-Fi')).dy;
    final shopping = tester.getTopLeft(find.text('Shopping')).dy;
    final height = tester.getSize(find.byType(MaterialApp)).height;
    expect(wifi, greaterThan(search));
    expect(shopping, greaterThan(wifi));
    expect(shopping, lessThan(height));

    await tester.tap(find.text('Wi-Fi'));
    await tester.pumpAndSettle();
    for (final text in ['Whole note', 'Password: tulip-42', 'guest: daisy-7']) {
      expect(find.text(text), findsOneWidget);
      expect(tester.getBottomLeft(find.text(text)).dy, lessThan(height));
    }
    await tester.tap(find.text('Password: tulip-42'));
    await tester.pumpAndSettle();
    expect(picked(), 'Password: tulip-42');
    expect(find.text('Insert into ZT Keyboard'), findsNothing);
  });

  testWidgets('Whole note hands back every line; a search with no match says why', (tester) async {
    final picked = await open(tester);
    await tester.enterText(find.byType(TextField), 'iban');
    await tester.pumpAndSettle();
    expect(find.textContaining('No notes match.'), findsOneWidget);
    expect(find.textContaining('Locked notes are not offered here.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'wi-fi');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wi-Fi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Whole note'));
    await tester.pumpAndSettle();
    expect(picked(), 'Wi-Fi\nHome\nPassword: tulip-42\nguest: daisy-7');
  });

  testWidgets('the picked text goes back over the text_pick channel', (tester) async {
    const channel = MethodChannel('dev.sagron.zerotrustnotes/text_pick');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'isPick' ? true : null;
    });
    await KeyboardPickListener.finish('hello');
    expect(calls.single.method, 'finish');
    expect(calls.single.arguments, {'text': 'hello'});
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
}
