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

/// Companion to sync_test.dart: that test pushes a note for a fresh test
/// account, after which its `encrypted_notes` row is deliberately corrupted
/// via direct SQL (flipping the last few base64 characters of `data_blob`,
/// which changes bytes inside the signed sealed box). This test signs back
/// into that same account on a "second device" (this emulator, with local
/// state cleared) and confirms Pull rejects the tampered blob instead of
/// silently applying it — this is what actually backs the "RLS isn't
/// enough, the signature check is load-bearing" claim in the plan.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'pull rejects a snapshot whose signed blob was tampered with server-side',
    (tester) async {
      // Filled in from the Supabase project after running sync_test.dart
      // and corrupting that run's row via SQL.
      const email = 'zerotrust-notes-m3-test+1785499010656@example.com';
      const accountPassword = 'AccountPassword123!';
      const vaultPassphrase = 'correct horse battery staple';

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

      // --- Sign in (not up) to the account whose row we corrupted. ---
      expect(find.text('Sign in'), findsWidgets);
      await tester.enterText(find.byKey(const Key('auth_email_field')), email);
      await tester.enterText(find.byKey(const Key('auth_password_field')), accountPassword);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // --- This is a "new device" for the vault: local salt/keys aren't
      // cached, so unlocking recovers them from the (untampered) profile
      // row over the network. ---
      expect(find.text('Zero-Trust Notes'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('unlock_passphrase_field')), vaultPassphrase);
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle(const Duration(seconds: 15));

      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('No notes yet. Tap + to create one.'), findsOneWidget);

      // --- Pull the (tampered) snapshot. ---
      await tester.tap(find.widgetWithIcon(IconButton, Icons.cloud_download_outlined));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Rejected: still no notes locally, and an error surfaced instead of
      // silently succeeding.
      expect(find.text('No notes yet. Tap + to create one.'), findsOneWidget);
      expect(find.textContaining('Pull failed'), findsOneWidget);
    },
  );
}
