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
    'sign up, push a note, clear local state, pull it back from Supabase',
    (tester) async {
      final uniqueSuffix = DateTime.now().millisecondsSinceEpoch;
      final email = 'zerotrust-notes-m3-test+$uniqueSuffix@example.com';
      const accountPassword = 'AccountPassword123!';
      const vaultPassphrase = 'correct horse battery staple';
      const noteTitle = 'M3 sync round-trip note';
      const noteBody = 'Pushed from device A, expected to reappear after Pull.';

      // Start from a clean slate: no cached salt/keys/last-sync-timestamp,
      // and no leftover local notes, from any previous run on this
      // emulator — otherwise this test isn't repeatable.
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

      await tester.pumpWidget(const ProviderScope(child: ZeroTrustNotesApp()));
      await tester.pumpAndSettle();

      // --- Sign up for a brand-new account. ---
      expect(find.text('Sign in'), findsWidgets);
      await tester.tap(find.text('New here? Create an account'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('auth_email_field')), email);
      await tester.enterText(find.byKey(const Key('auth_password_field')), accountPassword);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign up'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // --- Now on the vault unlock screen (signed in). ---
      expect(find.text('Zero-Trust Notes'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('unlock_passphrase_field')), vaultPassphrase);
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // --- Create a note. ---
      expect(find.text('Notes'), findsOneWidget);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('note_title_field')), noteTitle);
      await tester.enterText(find.byKey(const Key('note_body_field')), noteBody);
      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();
      expect(find.text(noteTitle), findsOneWidget);

      // --- Push it to Supabase. ---
      await tester.tap(find.widgetWithIcon(IconButton, Icons.sync));
      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(find.text('Idle'), findsOneWidget);

      // --- Delete the note locally (simulates a second, empty device). ---
      await tester.tap(find.text(noteTitle));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(find.text(noteTitle), findsNothing);

      // --- Pull it back down and confirm it's decrypted correctly. ---
      await tester.tap(find.widgetWithIcon(IconButton, Icons.cloud_download_outlined));
      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(find.text('Idle'), findsOneWidget);
      expect(find.text(noteTitle), findsOneWidget);
    },
  );
}
