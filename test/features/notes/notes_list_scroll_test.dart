import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';
import 'package:zerotrust_notes/src/features/notes/application/notes_layout.dart';
import 'package:zerotrust_notes/src/features/notes/application/notes_providers.dart';
import 'package:zerotrust_notes/src/features/notes/presentation/notes_list_page.dart';

import '../../support/fake_sync_backend.dart';
import '../../support/notes_device.dart';

void main() {
  const timeout = Timeout(Duration(seconds: 120));
  late Device phone;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> run(WidgetTester tester, Future<void> Function() body) async {
    var done = false;
    unawaited(body().whenComplete(() => done = true));
    for (var i = 0; i < 400 && !done; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(done, isTrue);
    await settle(tester);
  }

  Future<void> pumpList(WidgetTester tester, FakeSyncBackend server) async {
    phone = Device('phone', server);
    unawaited(phone.unlock());
    for (var i = 0; i < 50 && phone.container.read(notesRepositoryProvider) == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: phone.container,
        child: MaterialApp(
          localizationsDelegates: const [AppL10n.delegate, ...ZtLanguages.delegates],
          home: const NotesListPage(),
        ),
      ),
    );
    await settle(tester);
  }

  ScrollPosition position(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable).last).position;

  Future<void> done(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    phone.container.dispose();
    await tester.pump(const Duration(seconds: 10));
  }

  // The grid used to send the scroll back up as soon as the Pinned
  // section was out of sight, so the notes below could not be reached.
  for (final pinnedCount in [1, 3]) {
    testWidgets('with $pinnedCount pinned, the grid scrolls down to the last note', timeout: timeout, (
      tester,
    ) async {
      await pumpList(tester, FakeSyncBackend());
      await run(tester, () async {
        for (var i = 0; i < 60; i++) {
          await phone.repo.createNote(
            title: 'Note $i',
            body: 'line\n' * (1 + i % 5),
            pinned: i >= 60 - pinnedCount,
          );
        }
      });
      expect(find.text('Pinned'), findsOneWidget);
      expect(find.text('Note 0'), findsNothing);

      var last = -1.0;
      for (var i = 0; i < 40 && position(tester).pixels > last; i++) {
        last = position(tester).pixels;
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
        await tester.pumpAndSettle();
      }
      expect(position(tester).pixels, position(tester).maxScrollExtent);
      expect(position(tester).pixels, greaterThan(1500));
      // The oldest note, at the very end.
      expect(find.text('Note 0'), findsOneWidget);
      expect(tester.getRect(find.text('Note 0')).bottom, lessThan(600));
      await done(tester);
    });
  }

  for (final layout in NotesLayout.values) {
    testWidgets('the ${layout.name} stays where it was scrolled to while notes change', timeout: timeout, (
      tester,
    ) async {
      await pumpList(tester, FakeSyncBackend());
      if (layout == NotesLayout.list) {
        await tester.tap(find.byTooltip('Show as list'));
        await settle(tester);
      }
      await run(tester, () async {
        for (var i = 0; i < 80; i++) {
          await phone.repo.createNote(title: 'Note $i', body: 'line\n' * (1 + i % 5));
        }
      });
      for (var i = 0; i < 5; i++) {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
        await tester.pumpAndSettle();
      }
      final before = position(tester).pixels;
      expect(before, greaterThan(1000));

      // An old note is edited, which brings it to the top.
      final all = await tester.runAsync(() => phone.repo.fetchAll());
      await run(tester, () => phone.repo.updateNote(all!.last.copyWith(body: 'short')));
      expect(position(tester).pixels, before);

      await run(tester, () => phone.repo.createNote(title: 'New on top', body: 'x\ny\nz'));
      expect(position(tester).pixels, before);

      await run(tester, () => phone.container.read(ztSyncControllerProvider.notifier).syncNow());
      expect(position(tester).pixels, before);

      // Back at the top, the new note is first.
      for (var i = 0; i < 10; i++) {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, 300));
        await tester.pumpAndSettle();
      }
      expect(position(tester).pixels, 0);
      expect(find.text('New on top'), findsOneWidget);
      await done(tester);
    });
  }

  testWidgets('another view of the notes starts at its top', timeout: timeout, (tester) async {
    await pumpList(tester, FakeSyncBackend());
    await run(tester, () async {
      for (var i = 0; i < 80; i++) {
        await phone.repo.createNote(title: 'Note $i', body: 'line\n' * (1 + i % 5));
      }
    });
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(position(tester).pixels, greaterThan(500));

    await tester.tap(find.byTooltip('Show as list'));
    await settle(tester);
    expect(position(tester).pixels, 0);
    expect(find.text('Note 79'), findsOneWidget);
    await done(tester);
  });
}
