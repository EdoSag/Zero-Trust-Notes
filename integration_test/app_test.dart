import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zerotrust_notes/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'sign in, unlock, create a note, and confirm it survives a simulated cold restart',
    (tester) async {
      final uniqueSuffix = DateTime.now().millisecondsSinceEpoch;
      final email = 'zerotrust-notes-m1-test+$uniqueSuffix@example.com';
      const accountPassword = 'AccountPassword123!';
      const vaultPassphrase = 'correct horse battery staple';
      const noteTitle = 'M1 smoke test note';
      const noteBody = 'Created by the run skill to prove local persistence.';

      // Start from a clean slate so this test is repeatable across runs —
      // otherwise leftover local/cloud state makes the assertions below
      // fail even though the app is behaving correctly.
      await const FlutterSecureStorage().deleteAll();
      final documentsDir = await getApplicationDocumentsDirectory();
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        final file = File('${documentsDir.path}/note_vault.sqlite$suffix');
        if (file.existsSync()) file.deleteSync();
      }

      await dotenv.load(fileName: '.env');
      await Supabase.initialize(
        url: dotenv.env['SUPABASE_URL']!,
        publishableKey: dotenv.env['SUPABASE_ANON_KEY']!,
      );

      // --- First launch: no session, so the auth gate shows sign-in. ---
      await tester.pumpWidget(const ProviderScope(child: ZeroTrustNotesApp()));
      await tester.pumpAndSettle();

      expect(find.text('Sign in'), findsWidgets);
      await tester.tap(find.text('New here? Create an account'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('auth_email_field')), email);
      await tester.enterText(find.byKey(const Key('auth_password_field')), accountPassword);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign up'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // --- Signed in, vault boots locked. ---
      expect(find.text('Zero-Trust Notes'), findsOneWidget);
      expect(find.text('Unlock'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('unlock_passphrase_field')), vaultPassphrase);
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle(const Duration(seconds: 15));

      // --- Now on the notes list, empty. ---
      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('No notes yet. Tap + to create one.'), findsOneWidget);

      // --- Create a note. ---
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('New note'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('note_title_field')), noteTitle);
      await tester.enterText(find.byKey(const Key('note_body_field')), noteBody);
      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();

      // --- Back on the list, the note is there. ---
      expect(find.text('Notes'), findsOneWidget);
      expect(find.text(noteTitle), findsOneWidget);

      // --- Explicitly lock first (closes the DB connection cleanly, like a
      // real process exit would) before simulating a cold restart: fresh
      // widget tree + fresh Riverpod container so vault state resets to
      // VaultLocked, while the on-disk encrypted vault file and the
      // Supabase session both persist, exactly as they would across a real
      // app relaunch. ---
      await tester.tap(find.byTooltip('Lock vault'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(const ProviderScope(child: ZeroTrustNotesApp()));
      await tester.pumpAndSettle();

      // --- Session persisted, so we land straight on the unlock screen —
      // not back on the sign-in screen. ---
      expect(find.text('Zero-Trust Notes'), findsOneWidget);
      expect(find.text('Unlock'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('unlock_passphrase_field')), vaultPassphrase);
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      // --- The note created before "restart" is still there. ---
      expect(find.text('Notes'), findsOneWidget);
      expect(find.text(noteTitle), findsOneWidget);
    },
  );
}
