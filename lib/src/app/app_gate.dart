import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../features/export/application/export_temp_file_registry.dart';
import '../features/notes/application/notes_providers.dart';
import '../features/notes/presentation/notes_list_page.dart';
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

  /// Leaving the foreground deletes any in-flight export temp file. A key
  /// still waiting behind the recovery-key screen is zeroed too, so coming
  /// back asks for the password; a new recovery key can be made in Settings.
  /// Locking the open vault is the core's job: it follows the Auto-lock
  /// setting.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      final pending = _awaitingRecoveryKey;
      if (pending != null) {
        pending.dek.fillRange(0, pending.dek.length, 0);
        setState(() => _awaitingRecoveryKey = null);
      }
      ref.read(exportTempFileRegistryProvider).deleteAll();
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
      // Don't leave an editor or settings page open over a locked vault.
      if (next is VaultLocked) Navigator.of(context).popUntil((route) => route.isFirst);
    });
    ref.listen(currentUserProvider, (_, user) {
      if (user == null) {
        ref.read(vaultControllerProvider.notifier).lock();
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

    // Any touch counts as activity for auto-lock.
    return Listener(
      onPointerDown: (_) => ref.read(vaultControllerProvider.notifier).touch(),
      child: const _NotesHome(),
    );
  }
}

/// The notes list once the local store is open (and earlier notes moved into
/// it), which is also when sync starts.
class _NotesHome extends ConsumerWidget {
  const _NotesHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
