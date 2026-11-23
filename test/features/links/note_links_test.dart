import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/l10n/generated/app_l10n.dart';
import 'package:zerotrust_notes/src/features/links/note_links.dart';
import 'package:zerotrust_notes/src/features/notes/application/notes_providers.dart';
import 'package:zerotrust_notes/src/features/notes/domain/checklist_item.dart';
import 'package:zerotrust_notes/src/features/notes/domain/note.dart';
import 'package:zerotrust_notes/src/features/notes/presentation/note_editor_page.dart';

import '../../support/fake_sync_backend.dart';
import '../../support/notes_device.dart';
import '../notes/notes_list_page_test.dart' show finish, settle;

Note _note(String id, String title, {String body = '', int minute = 0, bool trashed = false}) {
  final at = DateTime.utc(2026, 11, 22, 9, minute);
  return Note(
    id: id,
    notebookId: null,
    title: title,
    body: body,
    createdAt: at,
    updatedAt: at,
    trashedAt: trashed ? at : null,
  );
}

void main() {
  group('NoteLinks', () {
    test('finds each linked title once, in order', () {
      expect(NoteLinks.titles('See [[Trip]] and [[ trip ]], then [[Packing  list]]. [[]] [x]'), [
        'Trip',
        'Packing list',
      ]);
    });

    test('resolves by title in any case, newest first, never from Trash', () {
      final notes = [
        _note('old', 'Trip', minute: 1),
        _note('new', 'trip', minute: 2),
        _note('gone', 'TRIP', minute: 3, trashed: true),
      ];
      expect(NoteLinks.resolve('TRIP', notes)?.id, 'new');
      expect(NoteLinks.resolve('Trip', notes, exceptId: 'new')?.id, 'old');
      expect(NoteLinks.resolve('Nothing', notes), isNull);
    });

    test('backlinks are the notes linking to the title', () {
      final notes = [
        _note('a', 'A', body: 'go to [[Trip]]'),
        _note('b', 'B', body: 'no links'),
        _note('t', 'Trip', body: 'links to itself [[trip]]'),
      ];
      expect(NoteLinks.backlinks('Trip', 't', notes).map((n) => n.id), ['a']);
      expect(NoteLinks.backlinks('', null, notes), isEmpty);
    });

    test('preview links open the note by title', () {
      final md = NoteLinks.toMarkdown('See [[Trip plan]]!');
      expect(md, 'See [Trip plan](ztnote:Trip%20plan)!');
      expect(NoteLinks.titleOfHref('ztnote:Trip%20plan'), 'Trip plan');
      expect(NoteLinks.titleOfHref('https://zerotrust.bz'), isNull);
    });

    test('a rename rewrites links in text and checklist items', () {
      expect(NoteLinks.renamed('[[trip]] and [[Other]]', 'Trip', 'Holiday'), '[[Holiday]] and [[Other]]');
      final list = _note('c', 'List').withChecklist([ChecklistItem.create('Read [[Trip]]')]);
      final renamed = NoteLinks.withRenamedLinks(list, 'Trip', 'Holiday')!;
      expect(renamed.checklist!.single.text, 'Read [[Holiday]]');
      expect(renamed.body, '- [ ] Read [[Holiday]]');
      expect(NoteLinks.withRenamedLinks(_note('x', 'X', body: 'none'), 'Trip', 'Holiday'), isNull);
    });
  });

  testWidgets('links open notes, show backlinks and follow a rename', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final phone = Device('phone', FakeSyncBackend());
    unawaited(phone.unlock());
    for (var i = 0; i < 50 && phone.container.read(notesRepositoryProvider) == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    final from = (await tester.runAsync(
      () => phone.repo.createNote(title: 'Plan', body: 'Pack for [[Trip]] and [[Budget]]'),
    ))!;
    await tester.runAsync(() => phone.repo.createNote(title: 'Trip', body: 'Tel Aviv'));
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
              ).push(MaterialPageRoute<void>(builder: (_) => NoteEditorPage(note: from))),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('open'));
    await settle(tester);

    // "Budget" doesn't exist yet; "Trip" does.
    expect(find.byKey(const ValueKey('note_link_out_Budget')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('note_link_out_Trip')));
    await settle(tester);
    expect(find.text('Tel Aviv'), findsOneWidget);
    expect(find.byKey(ValueKey('note_link_in_${from.id}')), findsOneWidget, reason: 'backlink');

    // Rename Trip; closing the editor rewrites the link in Plan.
    await tester.enterText(find.byKey(const Key('note_title_field')), 'Holiday');
    await settle(tester);
    await tester.pageBack();
    await settle(tester);
    await settle(tester);
    final plan = (await tester.runAsync(() => phone.repo.fetchAll()))!.firstWhere(
      (n) => n.id == from.id,
    );
    expect(plan.body, 'Pack for [[Holiday]] and [[Budget]]');

    // Plan's editor, still open, shows the new link and keeps it when edited.
    expect(find.byKey(const ValueKey('note_link_out_Holiday')), findsOneWidget);
    expect(find.byKey(const ValueKey('note_link_out_Trip')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('note_title_field')),
      'Plan for the week',
    );
    await settle(tester);
    await tester.pageBack();
    await settle(tester);
    await settle(tester);
    final edited = (await tester.runAsync(() => phone.repo.fetchAll()))!.firstWhere(
      (n) => n.id == from.id,
    );
    expect(edited.title, 'Plan for the week');
    expect(edited.body, 'Pack for [[Holiday]] and [[Budget]]');
    await finish(tester, phone);
  });
}
