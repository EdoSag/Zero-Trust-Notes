import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';
import 'package:zerotrust_notes/src/features/notes/application/notes_providers.dart';
import 'package:zerotrust_notes/src/features/other_import/other_apps_import_flow.dart';
import 'package:zerotrust_notes/src/features/other_import/other_apps_parser.dart';

import '../../support/fake_sync_backend.dart';
import '../../support/notes_device.dart';
import '../notes/notes_list_page_test.dart' show finish, settle;

void main() {
  testWidgets(
    'choose a Markdown zip: notes come in, and the summary says so',
    timeout: const Timeout(Duration(seconds: 60)),
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      final phone = Device(
        'phone',
        FakeSyncBackend(),
        overrides: [
          otherAppsFilePickerProvider.overrideWithValue(
            () async => {
              'Plan.md': utf8.encode('# Plan\n\nShip it'),
              'Shopping.md': utf8.encode('- [ ] Milk'),
            },
          ),
          otherAppsParserProvider.overrideWithValue((files) async => parseOtherAppsFiles(files)),
        ],
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
            theme: ZtTheme.light(),
            localizationsDelegates: const [AppL10n.delegate, ...ZtLanguages.delegates],
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => showOtherAppsImportFlow(context, ref),
                  child: const Text('import'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    await tester.tap(find.text('import'));
      await settle(tester);
      expect(find.textContaining('privacy.apple.com'), findsOneWidget);
      await tester.tap(find.byKey(const Key('other_import_choose')));
      await settle(tester);
      expect(find.text('Imported 2 notes'), findsOneWidget);
      expect(find.text('Everything came across.'), findsOneWidget);

      final notes = (await tester.runAsync(() => phone.repo.fetchAll()))!;
      expect(notes.map((n) => n.title), unorderedEquals(['Plan', 'Shopping']));
      expect(notes.firstWhere((n) => n.title == 'Shopping').isChecklist, isTrue);
      await finish(tester, phone);
    },
  );
}
