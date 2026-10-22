import 'package:zero_trust_core/zero_trust_core.dart';

/// In-memory Supabase Auth + `profiles`, reporting sign-in changes through
/// [onUserChanged] the way Supabase's auth stream would.
class FakeAccountBackend implements AccountBackend {
  FakeAccountBackend({required this.onUserChanged});

  final void Function(String? email) onUserChanged;
  final Map<String, String> authPasswords = {};
  final Map<String, ProfileRecord> profiles = {};
  String? _user;

  void _setUser(String? email) {
    _user = email;
    onUserChanged(email);
  }

  @override
  String? get currentUserId => _user;
  @override
  String? get currentEmail => _user;

  @override
  Future<void> signIn(String email, String authPassword) async {
    if (authPasswords[email] != authPassword) throw const InvalidCredentials();
    _setUser(email);
  }

  @override
  Future<void> signUp(String email, String authPassword) async {
    authPasswords[email] = authPassword;
    _setUser(email);
  }

  @override
  Future<void> updateAuthPassword(String authPassword) async =>
      authPasswords[_user!] = authPassword;

  @override
  Future<void> signOut() async => _setUser(null);

  @override
  Future<void> sendPasswordReset(String email, {String? redirectTo}) async {}

  @override
  Future<ProfileRecord?> fetchProfile() async => profiles[_user];

  @override
  Future<void> writeKeys(StoredKeys keys) async => profiles[_user!] = ProfileRecord(
    legacySalt: profiles[_user]?.legacySalt,
    keys: keys,
    authUpgraded: profiles[_user]?.authUpgraded ?? false,
  );

  @override
  Future<bool> needsLegacySignIn(String email) async {
    final p = profiles[email];
    return p != null &&
        p.legacySalt != null &&
        !p.authUpgraded &&
        (p.keys == null || p.keys!.legacyDek);
  }

  @override
  Future<void> markAuthUpgraded() async {
    final p = profiles[_user!]!;
    profiles[_user!] = ProfileRecord(legacySalt: p.legacySalt, keys: p.keys, authUpgraded: true);
  }

  @override
  Future<void> deleteAccount() async {
    authPasswords.remove(_user);
    profiles.remove(_user);
    _setUser(null);
  }
}
