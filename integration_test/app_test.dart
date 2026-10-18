import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/main.dart';

/// Runs against the real Supabase project in `.env`, which must have the
/// Zero-Trust-Core migrations applied.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Widget app() => ProviderScope(
    overrides: [ztAppConfigProvider.overrideWithValue(notesAppConfig)],
    child: const ZeroTrustNotesApp(),
  );

  testWidgets(
    'create an account, save the recovery key, add a note, and find it after a cold restart',
    (tester) async {
      final uniqueSuffix = DateTime.now().millisecondsSinceEpoch;
      final email = 'zerotrust-notes-test+$uniqueSuffix@example.com';
      const password = 'correct horse battery staple';
      const noteTitle = 'Smoke test note';
      const noteBody = 'Created by the integration test to prove local persistence.';

      // Start from a clean slate so this test is repeatable across runs.
      await const FlutterSecureStorage().deleteAll();
      final documentsDir = await getApplicationDocumentsDirectory();
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        final file = File('${documentsDir.path}/notes_v2.sqlite$suffix');
        if (file.existsSync()) file.deleteSync();
      }

      await dotenv.load(fileName: '.env');
      await Supabase.initialize(
        url: dotenv.env['SUPABASE_URL']!,
        publishableKey: dotenv.env['SUPABASE_ANON_KEY']!,
      );

      // --- First launch: no session, so the shared sign-in screen. ---
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create a Zero-Trust account'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Email'), email);
      await tester.enterText(find.widgetWithText(TextFormField, 'Password'), password);
      await tester.enterText(find.widgetWithText(TextFormField, 'Confirm password'), password);
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle(const Duration(seconds: 15));

      // --- The recovery key comes before any notes. ---
      expect(find.text('Save your recovery key'), findsOneWidget);
      await tester.tap(find.text('I saved my recovery key somewhere safe'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(find.text('No notes yet. Tap + to create one.'), findsOneWidget);

      // --- Create a note. ---
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('note_title_field')), noteTitle);
      await tester.enterText(find.byKey(const Key('note_body_field')), noteBody);
      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();
      expect(find.text(noteTitle), findsOneWidget);

      // --- Cold restart: fresh widget tree and providers, while the
      // encrypted file and the Supabase session persist. ---
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      // --- Session persisted, so straight to unlock, not sign-in. ---
      expect(find.text('Zero-Trust Notes is locked'), findsOneWidget);
      await tester.enterText(find.byType(TextField), password);
      await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
      await tester.pumpAndSettle(const Duration(seconds: 15));

      expect(find.text(noteTitle), findsOneWidget);
    },
  );
}
