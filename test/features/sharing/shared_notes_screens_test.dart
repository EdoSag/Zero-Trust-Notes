import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';
import 'package:zerotrust_notes/src/features/notebooks/application/notebooks_controller.dart';
import 'package:zerotrust_notes/src/features/notes/presentation/notes_list_page.dart';

import '../../support/sharing_people.dart';
import '../notes/notes_list_page_test.dart' show settle;

void main() {
  const timeout = Timeout(Duration(seconds: 90));

  late Person a;

  Future<void> open(WidgetTester tester, {Locale locale = const Locale('en')}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      a = Person(alice, InMemorySpaceServer(), 1);
      await a.open();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: a.c,
        child: MaterialApp(
          locale: locale,
          theme: ZtTheme.light(),
          localizationsDelegates: const [AppL10n.delegate, ...ZtLanguages.delegates],
          supportedLocales: AppL10n.supportedLocales,
          home: const NotesListPage(),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> run(WidgetTester tester, Future<void> Function() body) async {
    await tester.runAsync(body);
    await settle(tester);
  }

  /// Taps [finder] and lets real async work (store, sharing) run.
  Future<void> tapAndWait(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await settle(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    a.c.dispose();
    await tester.pump(const Duration(minutes: 10));
  }

  testWidgets('share a notebook from the list: explain, name, then the invite', timeout: timeout, (
    tester,
  ) async {
    await open(tester);
    await run(tester, () async {
      final trip = await a.c.read(notebooksRepositoryProvider)!.create('Trip');
      await a.device.repo.createNote(title: 'Packing', body: 'tent', notebookId: trip.id);
    });
    // Show the notebook, then share it from the menu.
    await tapAndWait(tester, find.text('Trip'));
    await tapAndWait(tester, find.byTooltip('More options'));
    await tapAndWait(tester, find.text('Share notebook'));
    expect(find.textContaining('Locked notes stay private'), findsOneWidget);
    await tapAndWait(tester, find.byKey(const Key('share_continue')));
    await tester.enterText(find.byKey(const Key('zt-sharing-name')), 'Alice');
    await tapAndWait(tester, find.byKey(const Key('zt-sharing-name-ok')));
    for (var i = 0; i < 20 && find.text('Invite to “Trip”').evaluate().isEmpty; i++) {
      await settle(tester);
    }
    expect(find.text('Invite to “Trip”'), findsOneWidget);

    // Back on the list: the notebook is the shared one, its note says so.
    await tester.pageBack();
    await settle(tester);
    expect(find.text('Alice (you)'), findsOneWidget);
    await tester.pageBack();
    await settle(tester);
    expect(a.notebooks.single.isShared, isTrue);
    expect(find.text('Packing'), findsOneWidget);
    final pill = find.byKey(const Key('note_shared_pill'));
    expect(pill, findsOneWidget);
    final card = tester.getRect(find.text('Packing'));
    expect(tester.getRect(pill).top, greaterThan(card.top), reason: 'pill under the title');
    await finish(tester);
  });

  testWidgets('a shared note: no lock or photos, People and sharing instead', timeout: timeout, (
    tester,
  ) async {
    await open(tester);
    await run(tester, () async {
      final note = await a.device.repo.createNote(title: 'Groceries', body: 'milk');
      await a.device.repo.shareNote(a.shared, note, myName: 'Alice', name: 'Groceries');
    });
    await tapAndWait(tester, find.text('Groceries'));
    expect(find.byKey(const Key('shared_note_chip')), findsOneWidget);
    await tapAndWait(tester, find.byTooltip('More options'));
    expect(find.text('People and sharing'), findsOneWidget);
    expect(find.text('Lock note'), findsNothing);
    expect(find.text('Add image'), findsNothing);
    await tapAndWait(tester, find.text('People and sharing'));
    expect(find.text('Groceries'), findsWidgets);
    expect(find.text('1 person'), findsOneWidget);
    expect(find.byKey(const Key('zt-space-invite')).hitTestable(), findsOneWidget);
    await finish(tester);
  });

  testWidgets('Hebrew: the join entry and sharing text are translated', timeout: timeout, (
    tester,
  ) async {
    await open(tester, locale: const Locale('he'));
    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await settle(tester);
    expect(find.text('הצטרפות עם הזמנה'), findsOneWidget);
    await tapAndWait(tester, find.byKey(const Key('drawer_join_shared')));
    expect(find.text('הצטרפות עם הזמנה'), findsWidgets);
    expect(
      Directionality.of(tester.element(find.byKey(const Key('zt-join-link')))),
      TextDirection.rtl,
    );
    await finish(tester);
  });
}
