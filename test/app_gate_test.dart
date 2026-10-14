import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User, AuthState;
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/main.dart';
import 'package:zerotrust_notes/src/app/auth_providers.dart';
import 'package:zerotrust_notes/src/core/db/local_note_vault.dart';
import 'package:zerotrust_notes/src/features/legacy_import/presentation/legacy_import.dart';
import 'package:zerotrust_notes/src/features/notes/application/notes_session.dart';
import 'package:zerotrust_notes/src/features/sync/application/sync_controller.dart';

import 'support/fake_account_backend.dart';
import 'support/fake_sync_backend.dart';

const email = 'edo@example.com';
const password = 'correct horse battery';

class FakeUser extends Notifier<User?> {
  @override
  User? build() => null;

  void set(String? email) => state = email == null
      ? null
      : User(
          id: email,
          appMetadata: const {},
          userMetadata: const {},
          aud: 'authenticated',
          createdAt: '2026-10-14T00:00:00Z',
          email: email,
        );
}

final fakeUserProvider = NotifierProvider<FakeUser, User?>(FakeUser.new);

void main() {
  late ProviderContainer container;

  setUp(() {
    late FakeAccountBackend backend;
    container = ProviderContainer(
      overrides: [
        ztAppConfigProvider.overrideWithValue(notesAppConfig),
        authStateChangesProvider.overrideWith((ref) => const Stream<AuthState>.empty()),
        currentUserProvider.overrideWith((ref) => ref.watch(fakeUserProvider)),
        accountServiceProvider.overrideWith(
          (ref) => AccountService(
            backend,
            params: const KdfParams(iterations: 1000),
            legacyParams: const KdfParams(iterations: 1000),
          ),
        ),
        syncBackendProvider.overrideWithValue(FakeSyncBackend()),
        deviceIdProvider.overrideWith((ref) async => 'test-device'),
        isOnlineProvider.overrideWithValue(() async => true),
        openNotesVaultProvider.overrideWithValue(
          (key) async => LocalNoteVault.forTesting(NativeDatabase.memory()),
        ),
        legacySourcesProvider.overrideWithValue((userId) => const []),
      ],
    );
    backend = FakeAccountBackend(
      onUserChanged: (email) => container.read(fakeUserProvider.notifier).set(email),
    );
  });

  tearDown(() => container.dispose());

  /// Crypto and the database run on real timers; let them finish.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
  }

  testWidgets('sign up shows the recovery key before any notes, then lock and unlock', (
    tester,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const ZeroTrustNotesApp()),
    );
    expect(find.text('Zero-Trust Notes'), findsOneWidget);

    await tester.tap(find.text('Create a Zero-Trust account'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), email);
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), password);
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm password'), password);
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await settle(tester);

    // The vault stays locked until the user confirms they saved the key.
    expect(find.text('Save your recovery key'), findsOneWidget);
    expect(container.read(vaultControllerProvider), isA<VaultLocked>());

    await tester.tap(find.text('I saved my recovery key somewhere safe'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await settle(tester);
    expect(find.text('No notes yet. Tap + to create one.'), findsOneWidget);

    container.read(vaultControllerProvider.notifier).lock();
    await settle(tester);
    expect(find.text('Zero-Trust Notes is locked'), findsOneWidget);
    expect(find.text(email), findsOneWidget);

    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await settle(tester);
    expect(find.text('No notes yet. Tap + to create one.'), findsOneWidget);

    await tester.tap(find.byTooltip('Settings'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Export all notes'), 200);
    expect(find.text('Export all notes'), findsOneWidget);

    // Locking cancels the auto-lock timer and pops back to the unlock screen.
    container.read(vaultControllerProvider.notifier).lock();
    await settle(tester);
    expect(find.text('Zero-Trust Notes is locked'), findsOneWidget);
  });
}
