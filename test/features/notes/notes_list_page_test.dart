import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_notes/src/features/notes/application/notes_providers.dart';
import 'package:zerotrust_notes/src/features/notes/domain/checklist_item.dart';
import 'package:zerotrust_notes/src/features/notes/presentation/notes_list_page.dart';

import '../../support/fake_sync_backend.dart';
import '../../support/notes_device.dart';

void main() {
  const timeout = Timeout(Duration(seconds: 60));
  late Device phone;

  Future<void> pumpList(WidgetTester tester) async {
    phone = Device('phone', FakeSyncBackend());
    // Unlocking opens the store with real I/O, so let it run outside the
    // fake clock.
    unawaited(phone.unlock());
    for (var i = 0; i < 50 && phone.container.read(notesRepositoryProvider) == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: phone.container,
        child: const MaterialApp(home: NotesListPage()),
      ),
    );
    await settle(tester);
  }

  Future<void> addNotes(WidgetTester tester, Future<void> Function() body) async {
    var done = false;
    unawaited(body().whenComplete(() => done = true));
    for (var i = 0; i < 50 && !done; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(done, isTrue);
    await settle(tester);
  }

  testWidgets('pinned notes show under Pinned, and a checklist previews its items', timeout: timeout, (tester) async {
    await pumpList(tester);
    await addNotes(tester, () async {
      await phone.repo.createNote(title: 'Regular', body: 'text');
      await phone.repo.createNote(title: 'Top', body: '', pinned: true);
      await phone.repo.createNote(
        title: 'Shopping',
        body: '',
        checklist: [ChecklistItem.create('milk'), ChecklistItem.create('eggs', checked: true)],
      );
    });

    expect(find.text('Pinned'), findsOneWidget);
    expect(find.text('Others'), findsOneWidget);
    expect(find.text('milk'), findsOneWidget);
    expect(find.text('+ 1 ticked item'), findsOneWidget);

    // Grid and list both show the notes.
    await tester.tap(find.byTooltip('Show as list'));
    await settle(tester);
    expect(find.text('Regular'), findsOneWidget);
    expect(find.byTooltip('Show as grid'), findsOneWidget);
    await finish(tester, phone);
  });

  testWidgets('moving to Trash hides a note until it is restored from the Trash view', timeout: timeout, (tester) async {
    await pumpList(tester);
    await addNotes(tester, () => phone.repo.createNote(title: 'Doomed', body: 'x'));

    await tester.longPress(find.text('Doomed'));
    await settle(tester);
    await tester.tap(find.text('Move to Trash'));
    await settle(tester);
    expect(find.text('Doomed'), findsNothing);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await settle(tester);
    await tester.tap(find.text('Trash'));
    await settle(tester);
    expect(find.text('Doomed'), findsOneWidget);
    expect(find.text('Notes in Trash are deleted after 30 days.'), findsOneWidget);

    await tester.longPress(find.text('Doomed'));
    await settle(tester);
    await tester.tap(find.text('Restore'));
    await settle(tester);
    expect(find.text('Doomed'), findsNothing);
    expect(find.text('No notes in Trash.'), findsOneWidget);
    await finish(tester, phone);
  });

  testWidgets('search finds checklist items and the checklist filter narrows it', timeout: timeout, (tester) async {
    await pumpList(tester);
    await addNotes(tester, () async {
      await phone.repo.createNote(title: 'Trip', body: 'passport in a note');
      await phone.repo.createNote(
        title: 'Packing',
        body: '- [ ] passport',
        checklist: [ChecklistItem.create('passport')],
      );
    });

    await tester.tap(find.byTooltip('Search notes'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'passport');
    await settle(tester);
    expect(find.text('Trip'), findsOneWidget);
    expect(find.text('Packing'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'Checklists'));
    await settle(tester);
    expect(find.text('Trip'), findsNothing);
    expect(find.text('Packing'), findsOneWidget);
    await finish(tester, phone);
  });
}

/// Unmounts, closes the store and lets snack bars, sync and Riverpod's
/// retry timers run out.
Future<void> finish(WidgetTester tester, Device phone) async {
  await tester.pumpWidget(const SizedBox());
  phone.container.dispose();
  await tester.pump(const Duration(seconds: 10));
}

/// Lets store reads (real async) and animations finish.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}
