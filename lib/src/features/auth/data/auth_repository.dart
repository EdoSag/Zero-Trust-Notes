import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin wrapper around Supabase Auth. This is account-level identity only —
/// it has nothing to do with the vault passphrase or Tier-2 encryption key.
/// A Supabase session proves who the user is to the backend; it never
/// unlocks the local vault.
class AuthRepository {
  AuthRepository({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  User? get currentUser => _client.auth.currentUser;

  Future<void> signUp({required String email, required String password}) async {
    await _client.auth.signUp(email: email, password: password);
  }

  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() => _client.auth.signOut();
}
