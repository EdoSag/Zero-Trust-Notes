import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/features/auth/application/auth_controller.dart';
import 'src/features/auth/presentation/auth_screen.dart';
import 'src/features/export/application/export_temp_file_registry.dart';
import 'src/features/notes/presentation/notes_list_page.dart';
import 'src/features/vault/application/vault_controller.dart';
import 'src/features/vault/application/vault_state.dart';
import 'src/features/vault/presentation/unlock_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    publishableKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(const ProviderScope(child: ZeroTrustNotesApp()));
}

class ZeroTrustNotesApp extends StatelessWidget {
  const ZeroTrustNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zero-Trust Notes',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
      home: const _AuthGate(),
    );
  }
}

/// A Supabase session establishes account identity; it never implies the
/// vault is unlocked. Signed out -> [AuthScreen]. Signed in -> hand off to
/// the vault lifecycle gate, which always starts locked.
class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    return currentUser == null ? const AuthScreen() : const _VaultLifecycleGate();
  }
}

/// Locks the vault (closing the DB and zeroing its in-memory Tier-2 key)
/// and force-deletes any in-flight export temp file whenever the app
/// leaves the foreground — always starts locked on a cold launch, since
/// the vault state machine never assumes a prior session.
class _VaultLifecycleGate extends ConsumerStatefulWidget {
  const _VaultLifecycleGate();

  @override
  ConsumerState<_VaultLifecycleGate> createState() => _VaultLifecycleGateState();
}

class _VaultLifecycleGateState extends ConsumerState<_VaultLifecycleGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      ref.read(vaultControllerProvider.notifier).lock();
      ref.read(exportTempFileRegistryProvider).deleteAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final vaultState = ref.watch(vaultControllerProvider);
    return switch (vaultState) {
      VaultUnlocked() || VaultSyncing() || VaultSyncConflictDetected() => const NotesListPage(),
      VaultLocked() || VaultUnlocking() || VaultError() => const UnlockScreen(),
    };
  }
}
