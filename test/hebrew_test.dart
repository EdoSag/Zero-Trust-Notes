import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';
import 'package:zerotrust_notes/src/features/notes/application/notes_providers.dart';
import 'package:zerotrust_notes/src/features/notes/domain/checklist_item.dart';
import 'package:zerotrust_notes/src/features/notes/domain/note_color.dart';
import 'package:zerotrust_notes/src/features/notes/presentation/note_actions.dart';
import 'package:zerotrust_notes/src/features/notes/presentation/notes_list_page.dart';

import 'features/notes/notes_list_page_test.dart' show finish, settle;
import 'support/fake_sync_backend.dart';
import 'support/notes_device.dart';

void main() {
  test('every English string has a Hebrew translation with the same placeholders', () {
    Map<String, dynamic> read(String lang) =>
        jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync()) as Map<String, dynamic>;
    final en = read('en');
    final he = read('he');
    final placeholder = RegExp(r'\{(\w+)[,}]');
    for (final key in en.keys.where((k) => !k.startsWith('@'))) {
      expect(he[key], isA<String>(), reason: 'app_he.arb is missing "$key"');
      Set<String?> names(String text) => placeholder.allMatches(text).map((m) => m[1]).toSet();
      expect(names(he[key] as String), names(en[key] as String), reason: 'placeholders differ in "$key"');
    }
  });

  testWidgets('Hebrew: the notes list is translated and right-to-left', timeout: const Timeout(Duration(seconds: 60)), (
    tester,
  ) async {
    final phone = Device('phone', FakeSyncBackend());
    unawaited(phone.unlock());
    for (var i = 0; i < 50 && phone.container.read(notesRepositoryProvider) == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: phone.container,
        child: MaterialApp(
          locale: ZtLanguages.hebrew,
          supportedLocales: ZtLanguages.supported,
          localizationsDelegates: const [AppL10n.delegate, ...ZtLanguages.delegates],
          home: const NotesListPage(),
        ),
      ),
    );
    var done = false;
    unawaited(() async {
      await phone.repo.createNote(title: 'Top', body: '', pinned: true);
      await phone.repo.createNote(
        title: 'Shopping',
        body: '',
        checklist: [ChecklistItem.create('milk'), ChecklistItem.create('eggs', checked: true)],
      );
    }().whenComplete(() => done = true));
    for (var i = 0; i < 50 && !done; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await settle(tester);

    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(Directionality.of(tester.element(find.byType(NotesListPage))), TextDirection.rtl);
    expect(find.text('פתקים'), findsWidgets); // App bar: "Notes".
    expect(find.text('+ פריט אחד מסומן'), findsOneWidget);

    // The "Pinned" heading's letters sit on the right.
    final heading = tester.renderObject<RenderParagraph>(find.text('מוצמדים'));
    final glyphs = heading.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 7));
    final left = glyphs.map((b) => b.left).reduce((a, b) => a < b ? a : b);
    expect(heading.localToGlobal(Offset(left, 0)).dx, greaterThan(width / 2));

    // The new-note button sits bottom-left, Material's end side in Hebrew.
    final fab = tester.getRect(find.byTooltip('יצירת פתק חדש'));
    expect(fab.center.dx, lessThan(width / 2));

    // Text with no context (colour names, reminder times) follows too.
    expect(NoteColor.red.displayName, 'אדום');
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    expect(formatReminder(DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 8)), 'מחר, 8:00');

    await finish(tester, phone);
  });
}
