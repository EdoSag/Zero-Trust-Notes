import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../features/export/application/export_temp_file_registry.dart';
import '../features/notes/application/notes_providers.dart';
import '../features/notes/presentation/note_editor_page.dart';
import '../features/notes/presentation/notes_list_page.dart';
import '../features/reminders/reminder_scheduler.dart';
import '../features/sharing/note_sharing.dart';
import '../features/sharing/share_intent_listener.dart';
import '../features/widgets/application/home_widget_sync_service.dart';
import '../features/widgets/application/pending_widget_action_controller.dart';
import '../features/widgets/application/widget_launch_listener.dart';
import '../features/widgets/domain/pending_widget_action.dart';
import '../features/widgets/presentation/note_picker_page.dart';
import 'auth_providers.dart';

/// Routes between the shared account screens and the notes list.
///
/// Signed out: sign in or create an account. Signed in but locked (cold
/// start, background, auto-lock): unlock with the account password. A new
/// recovery key is always shown, and confirmed, before the vault opens.
class AppGate extends ConsumerStatefulWidget {
  const AppGate({super.key});

  @override
  ConsumerState<AppGate> createState() => _AppGateState();
}

class _AppGateState extends ConsumerState<AppGate> with WidgetsBindingObserver {
  /// Stays on the sign-in screen until it hands back a result, even though
  /// Supabase reports the session a moment earlier.
  late bool _signingIn = ref.read(currentUserProvider) == null;
  UnlockResult? _awaitingRecoveryKey;
  late final WidgetLaunchListener _widgetLaunchListener;
  late final ShareIntentListener _shareIntentListener;
  StreamSubscription<String>? _reminderTaps;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _widgetLaunchListener = WidgetLaunchListener(ref);
    unawaited(_widgetLaunchListener.start());
    // Text and images shared from other apps open as a new note.
    _shareIntentListener = ShareIntentListener(ref);
    unawaited(_shareIntentListener.start());
    // Images sent from an earlier session are no longer needed.
    unawaited(ref.read(outgoingShareFilesProvider).clear());
    // A tapped reminder opens its note, after unlock if needed.
    _reminderTaps = ref
        .read(reminderSchedulerProvider)
        .taps
        .listen(
          (noteId) => ref.read(pendingWidgetActionProvider.notifier).set(OpenNote(noteId)),
          onError: (Object _) {},
        );
  }

  @override
  void dispose() {
    _reminderTaps?.cancel();
    _widgetLaunchListener.dispose();
    _shareIntentListener.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Leaving the foreground deletes any in-flight export temp file and every
  /// home-screen widget preview. A key still waiting behind the recovery-key
  /// screen is zeroed too, so coming back asks for the password; a new
  /// recovery key can be made in Settings. Locking the open vault is the
  /// core's job: it follows the Auto-lock setting.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      final pending = _awaitingRecoveryKey;
      if (pending != null) {
        pending.dek.fillRange(0, pending.dek.length, 0);
        setState(() => _awaitingRecoveryKey = null);
      }
      ref.read(exportTempFileRegistryProvider).deleteAll();
      unawaited(const HomeWidgetSyncService().clearAllPlaintext());
    }
    // Back from the share sheet: the other app has read the images Notes
    // decrypted for it.
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(outgoingShareFilesProvider).clear());
    }
  }

  void _onUnlocked(UnlockResult result) {
    if (result.newRecoveryKey != null) {
      setState(() {
        _signingIn = false;
        _awaitingRecoveryKey = result;
      });
      return;
    }
    setState(() => _signingIn = false);
    ref.read(vaultControllerProvider.notifier).unlock(result.dek, legacyDek: result.legacyDek);
  }

  void _forgotPassword() => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const ZtForgotPasswordScreen()));

  @override
  Widget build(BuildContext context) {
    ref.listen(vaultControllerProvider, (_, next) {
      if (next is VaultLocked) {
        // Don't leave an editor or settings page open over a locked vault.
        Navigator.of(context).popUntil((route) => route.isFirst);
        // Writing previews (and acting on widget taps) is _NotesHome's job.
        unawaited(const HomeWidgetSyncService().clearAllPlaintext());
      }
    });
    ref.listen(currentUserProvider, (_, user) {
      if (user == null) {
        ref.read(vaultControllerProvider.notifier).lock();
        // Signed out: this account's reminders shouldn't fire on this phone.
        unawaited(ref.read(reminderSchedulerProvider).cancelAll().catchError((Object _) {}));
        setState(() => _signingIn = true);
      }
    });

    final pending = _awaitingRecoveryKey;
    if (pending != null) {
      return ZtRecoveryKeyScreen(
        recoveryKey: pending.newRecoveryKey!,
        onDone: () {
          setState(() => _awaitingRecoveryKey = null);
          ref
              .read(vaultControllerProvider.notifier)
              .unlock(pending.dek, legacyDek: pending.legacyDek);
        },
      );
    }

    if (ref.watch(passwordRecoveryProvider)) {
      return ZtResetPasswordScreen(
        onUnlocked: (result) {
          ref.read(passwordRecoveryProvider.notifier).done();
          _onUnlocked(result);
        },
      );
    }

    final user = ref.watch(currentUserProvider);
    if (user == null || _signingIn) {
      return ZtSignInScreen(onUnlocked: _onUnlocked, onForgotPassword: _forgotPassword);
    }

    if (ref.watch(vaultControllerProvider) is VaultLocked) {
      return ZtUnlockScreen(
        email: user.email,
        onUnlocked: _onUnlocked,
        onSignOut: () => ref.read(accountServiceProvider).signOut(),
        onForgotPassword: _forgotPassword,
      );
    }

    return const _NotesHome();
  }
}

/// Counts any touch as activity for auto-lock. Goes in
/// `MaterialApp.builder`, above the navigator, so touches on pushed screens
/// (an editor, Settings) count too and the app doesn't lock mid-edit.
class AutoLockActivity extends ConsumerWidget {
  const AutoLockActivity({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Listener(
    onPointerDown: (_) => ref.read(vaultControllerProvider.notifier).touch(),
    child: child,
  );
}

/// The notes list once the local store is open (and earlier notes moved into
/// it), which is also when sync starts.
///
/// Mounted only while the vault is unlocked, so this is also where
/// home-screen widget previews are written and widget taps are acted on.
class _NotesHome extends ConsumerStatefulWidget {
  const _NotesHome();

  @override
  ConsumerState<_NotesHome> createState() => _NotesHomeState();
}

class _NotesHomeState extends ConsumerState<_NotesHome> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _syncWidgetPreviews);
    ref.listenManual(notesListProvider, (_, _) {
      _syncWidgetPreviews();
      _maybeConsumePendingWidgetAction();
    }, fireImmediately: true);
    ref.listenManual(pendingWidgetActionProvider, (_, next) {
      if (next != null) _maybeConsumePendingWidgetAction();
    });
    // Reminders set on any device are handed to this phone's OS.
    ref.listenManual(allNotesProvider, (_, next) {
      final notes = next.value;
      if (notes == null) return;
      unawaited(
        ref
            .read(reminderSchedulerProvider)
            .sync(ScheduledReminder.fromNotes(notes, DateTime.now()))
            .catchError((Object _) {}),
      );
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// Pushes a fresh widget preview. Clearing on lock and on pause is
  /// [AppGate]'s job.
  void _syncWidgetPreviews() {
    // Only while on screen: a sync arriving in the background must not
    // write plaintext back after AppGate cleared it on pause.
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    if (ref.read(vaultControllerProvider) is! VaultUnlocked) return;
    final notes = ref.read(notesListProvider).value;
    if (notes == null) return;
    unawaited(const HomeWidgetSyncService().writeUnlockedPreviews(notes));
  }

  /// Performs the navigation a widget tap asked for, once the notes are
  /// loaded — reachable both when unlock happens after the tap (cold start)
  /// and when the tap happens while already unlocked.
  void _maybeConsumePendingWidgetAction() {
    final notes = ref.read(notesListProvider).value;
    if (notes == null) return;
    final action = ref.read(pendingWidgetActionProvider);
    if (action == null) return;
    ref.read(pendingWidgetActionProvider.notifier).clear();

    // Not while a listener is notifying: navigation rebuilds widgets.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (action) {
        case OpenNewNote():
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NoteEditorPage()));
        case OpenNote(:final noteId):
          final matches = notes.where((note) => note.id == noteId);
          if (matches.isEmpty) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(
                content: Text('That note could not be found — it may have been deleted.'),
              ),
            );
          } else {
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => NoteEditorPage(note: matches.first)));
          }
        case CreateNoteFromShare(:final content):
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => NoteEditorPage(shared: content)));
        case ConfigureNoteWidget(:final appWidgetId):
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => NotePickerPage(appWidgetId: appWidgetId)));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return switch (ref.watch(notesStoreProvider)) {
      AsyncData() => const NotesListPage(),
      AsyncError(:final error) when error is! VaultIsLocked => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Couldn\'t open your notes on this device.'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(notesStoreProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}
