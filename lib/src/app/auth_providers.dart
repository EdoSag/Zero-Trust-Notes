import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Every Supabase auth event (sign-in, sign-out, password-recovery link).
final authStateChangesProvider = StreamProvider<AuthState>(
  (ref) => Supabase.instance.client.auth.onAuthStateChange,
);

/// The signed-in account, or null. A session only proves identity to the
/// backend; it never unlocks the vault.
final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateChangesProvider);
  return Supabase.instance.client.auth.currentUser;
});

/// True after the user opens a "reset password" email link, until they
/// finish `ZtResetPasswordScreen`.
final passwordRecoveryProvider = NotifierProvider<PasswordRecovery, bool>(PasswordRecovery.new);

class PasswordRecovery extends Notifier<bool> {
  @override
  bool build() {
    ref.listen(authStateChangesProvider, (_, next) {
      if (next.value?.event == AuthChangeEvent.passwordRecovery) state = true;
    });
    return false;
  }

  void done() => state = false;
}
