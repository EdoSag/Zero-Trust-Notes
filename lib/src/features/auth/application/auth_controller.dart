import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/auth_repository.dart';

final _authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository());

/// Drives all UI that needs to react to "is anyone signed in": true whenever
/// there's a live Supabase session, independent of vault lock state.
final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(_authRepositoryProvider).authStateChanges;
});

final currentUserProvider = Provider<User?>((ref) {
  // Also watch the stream so this recomputes on sign-in/out, not just once.
  ref.watch(authStateChangesProvider);
  return ref.watch(_authRepositoryProvider).currentUser;
});

sealed class AuthFormState {
  const AuthFormState();
}

class AuthIdle extends AuthFormState {
  const AuthIdle();
}

class AuthSubmitting extends AuthFormState {
  const AuthSubmitting();
}

class AuthFormError extends AuthFormState {
  const AuthFormError(this.message);

  final String message;
}

final authControllerProvider = NotifierProvider<AuthController, AuthFormState>(
  AuthController.new,
);

class AuthController extends Notifier<AuthFormState> {
  late final AuthRepository _repository = ref.read(_authRepositoryProvider);

  @override
  AuthFormState build() => const AuthIdle();

  Future<void> signUp({required String email, required String password}) async {
    state = const AuthSubmitting();
    try {
      await _repository.signUp(email: email, password: password);
      state = const AuthIdle();
    } on AuthException catch (error) {
      state = AuthFormError(error.message);
    } catch (error) {
      state = AuthFormError('Sign up failed: $error');
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    state = const AuthSubmitting();
    try {
      await _repository.signIn(email: email, password: password);
      state = const AuthIdle();
    } on AuthException catch (error) {
      state = AuthFormError(error.message);
    } catch (error) {
      state = AuthFormError('Sign in failed: $error');
    }
  }

  Future<void> signOut() => _repository.signOut();
}
