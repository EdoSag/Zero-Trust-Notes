import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/features/auth/application/auth_controller.dart';
import 'src/features/auth/presentation/auth_screen.dart';
import 'src/features/export/application/export_temp_file_registry.dart';
import 'src/features/notes/application/notes_controller.dart';
import 'src/features/notes/domain/note.dart';
import 'src/features/notes/presentation/note_editor_page.dart';
import 'src/features/notes/presentation/notes_list_page.dart';
import 'src/features/vault/application/vault_controller.dart';
import 'src/features/vault/application/vault_state.dart';
import 'src/features/vault/presentation/unlock_screen.dart';
import 'src/features/widgets/application/home_widget_sync_service.dart';
import 'src/features/widgets/application/pending_widget_action_controller.dart';
import 'src/features/widgets/application/widget_launch_listener.dart';
import 'src/features/widgets/domain/pending_widget_action.dart';
import 'src/features/widgets/presentation/note_picker_page.dart';
import 'src/shared/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    publishableKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  // Defensive: the vault always cold-starts locked, but if the OS killed a
  // previous process without ever running VaultController.lock() (e.g. a
  // task kill rather than a clean background pause), a home-screen widget
  // preview cached mid-session could otherwise survive until the next
  // explicit lock. Clearing here unconditionally means "locked" is the
  // only state a widget can ever show right after a cold start.
  await const HomeWidgetSyncService().clearAllPlaintext();

  runApp(const ProviderScope(child: ZeroTrustNotesApp()));
}

bool _isVaultUnlockedLike(VaultState state) =>
    state is VaultUnlocked || state is VaultSyncing || state is VaultSyncConflictDetected;

class ZeroTrustNotesApp extends StatelessWidget {
  const ZeroTrustNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zero-Trust Notes',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
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
  late final WidgetLaunchListener _widgetLaunchListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _widgetLaunchListener = WidgetLaunchListener(ref);
    unawaited(_widgetLaunchListener.start());
  }

  @override
  void dispose() {
    _widgetLaunchListener.dispose();
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

  /// Pushes a fresh widget preview whenever the vault is (or becomes)
  /// unlocked-like. There's no corresponding "on lock, clear" branch here —
  /// that happens synchronously inside `VaultController.lock()` itself, so
  /// it can't be skipped by a code path that forgets to call this gate.
  void _syncWidgetPreviews() {
    final vaultState = ref.read(vaultControllerProvider);
    if (!_isVaultUnlockedLike(vaultState)) return;
    final notes = ref.read(notesListProvider).value;
    if (notes == null) return;
    unawaited(const HomeWidgetSyncService().writeUnlockedPreviews(notes));
  }

  /// Performs the navigation a widget tap asked for, but only once the
  /// vault is confirmed unlocked — reachable both when unlock happens after
  /// the tap (cold start) and when the tap happens while already unlocked.
  void _maybeConsumePendingWidgetAction() {
    if (!_isVaultUnlockedLike(ref.read(vaultControllerProvider))) return;
    final action = ref.read(pendingWidgetActionProvider);
    if (action == null) return;
    ref.read(pendingWidgetActionProvider.notifier).clear();

    switch (action) {
      case OpenNewNote():
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NoteEditorPage()));
      case OpenNote(:final noteId):
        final notes = ref.read(notesListProvider).value ?? const <Note>[];
        final matches = notes.where((note) => note.id == noteId);
        if (matches.isEmpty) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(content: Text('That note could not be found — it may have been deleted.')),
          );
        } else {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => NoteEditorPage(note: matches.first)));
        }
      case ConfigureNoteWidget(:final appWidgetId):
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => NotePickerPage(appWidgetId: appWidgetId)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vaultState = ref.watch(vaultControllerProvider);

    ref.listen<VaultState>(vaultControllerProvider, (previous, next) {
      _syncWidgetPreviews();
      _maybeConsumePendingWidgetAction();
    });
    ref.listen(notesListProvider, (previous, next) => _syncWidgetPreviews());
    ref.listen(pendingWidgetActionProvider, (previous, next) {
      if (next != null) _maybeConsumePendingWidgetAction();
    });

    return switch (vaultState) {
      VaultUnlocked() || VaultSyncing() || VaultSyncConflictDetected() => const NotesListPage(),
      VaultLocked() || VaultUnlocking() || VaultError() => const UnlockScreen(),
    };
  }
}
