import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/l10n/generated/app_l10n.dart';
import 'package:zerotrust_notes/src/features/notes/application/notes_providers.dart';
import 'package:zerotrust_notes/src/features/notes/domain/checklist_item.dart';
import 'package:zerotrust_notes/src/features/notes/domain/note.dart';
import 'package:zerotrust_notes/src/features/templates/note_template.dart';
import 'package:zerotrust_notes/src/features/templates/templates_repository.dart';
import 'package:zerotrust_notes/src/features/templates/templates_views.dart';

import '../../support/fake_sync_backend.dart';
import '../../support/notes_device.dart';
import '../notes/notes_list_page_test.dart' show finish, settle;

void main() {
  final en = lookupAppL10n(const Locale('en'));
  final he = lookupAppL10n(const Locale('he'));

  group('NoteTemplate', () {
    test('fills in the date, weekday and time', () {
      const template = NoteTemplate(
        id: 't',
        name: 'Day',
        title: '{{date}}',
        body: '{{weekday}} at {{ TIME }}, {{longdate}} {{other}}',
      );
      final fill = template.fill(DateTime(2026, 11, 22, 9, 5), localeName: 'en');
      expect(fill.title, '2026-11-22');
      expect(fill.body, 'Sunday at 09:05, Sunday, November 22, 2026 {{other}}');
      expect(fill.checklist, isNull);
    });

    test('a checklist template gives new, unticked items', () {
      final note = Note(
        id: 'n',
        notebookId: null,
        title: 'Packing',
        body: '',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        checklist: [ChecklistItem.create('Passport', checked: true)],
      );
      final template = NoteTemplate.fromNote(note, id: 't', name: 'Packing');
      expect(template.checklist!.single.checked, isFalse);
      final back = NoteTemplate.fromItem(
        LocalItem(itemId: 't', updatedAt: DateTime.utc(2026), json: template.toItemJson()),
      );
      expect(back.name, 'Packing');
      expect(back.checklist!.single.text, 'Passport');
      final a = back.fill(DateTime(2026), localeName: 'en').checklist!.single;
      final b = back.fill(DateTime(2026), localeName: 'en').checklist!.single;
      expect(a.id, isNot(b.id), reason: 'each note gets its own item ids');
    });

    test('templates are never read as notes, and built-ins exist in both languages', () {
      expect(Note.isNoteJson(const NoteTemplate(id: 't', name: 'x').toItemJson()), isFalse);
      for (final l in [en, he]) {
        final builtIns = NoteTemplate.builtIns(l);
        expect(builtIns.map((t) => t.id), ['builtin:journal', 'builtin:meeting', 'builtin:todo']);
        expect(builtIns.first.title, '{{date}}', reason: "the daily note's title is the date");
        expect(builtIns.last.checklist, isNotEmpty);
      }
    });
  });

  testWidgets("today's note: made from the daily template, then reopened", (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final phone = Device('phone', FakeSyncBackend());
    unawaited(phone.unlock());
    for (var i = 0; i < 50 && phone.container.read(notesRepositoryProvider) == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    phone.container.listen(templatesRepositoryProvider, (_, _) {});
    final templates = phone.container.read(templatesRepositoryProvider)!;
    final own = (await tester.runAsync(
      () => templates.add((id) => NoteTemplate(id: id, name: 'Mine', body: 'Mood: ')),
    ))!;
    // A read and a write in one go need the test clock to move, as in the app.
    var marked = false;
    unawaited(templates.setDaily(own.id).then((_) => marked = true));
    for (var i = 0; i < 20 && !marked; i++) {
      await settle(tester);
    }
    expect(marked, isTrue);
    phone.container.listen(ownTemplatesProvider, (_, _) {});
    phone.container.listen(notesListProvider, (_, _) {});
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: phone.container,
        child: MaterialApp(
          theme: ZtTheme.light(),
          localizationsDelegates: const [AppL10n.delegate, ...ZtLanguages.delegates],
          home: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => openDailyNote(context, ref),
              child: const Text('today'),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    final today = NoteTemplate.isoDate(DateTime.now());
    await tester.tap(find.text('today'));
    await settle(tester);
    expect(find.text(today), findsOneWidget);
    expect(find.text('Mood: '), findsOneWidget);
    await tester.enterText(find.byKey(const Key('note_body_field')), 'Mood: good');
    await settle(tester);
    await tester.pageBack();
    await settle(tester);

    await tester.tap(find.text('today'));
    await settle(tester);
    expect(find.text('Mood: good'), findsOneWidget, reason: 'the same note opens again');
    await tester.pageBack();
    await settle(tester);
    final notes = (await tester.runAsync(() => phone.repo.fetchAll()))!;
    expect(notes.map((n) => n.title), [today]);
    await finish(tester, phone);
  });
}
