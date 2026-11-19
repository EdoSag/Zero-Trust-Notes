import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Where the links in account emails lead. Both addresses must be allowed in
/// Supabase (Authentication > URL Configuration > Redirect URLs:
/// https://zerotrust.bz/auth/**), or Supabase sends people to the Site URL.
abstract final class EmailLinks {
  /// The password-reset email links straight here:
  /// https://zerotrust.bz/auth/notes/#token_hash=…&type=recovery
  /// (see the reset-password email template). Android opens it in this app
  /// (App Links: the intent filter in AndroidManifest.xml and the website's
  /// /.well-known/assetlinks.json), whatever the default browser is, and
  /// [listen] turns it into the password-recovery sign-in, after which
  /// AppGate shows ZtResetPasswordScreen. Where the app can't open it (iOS
  /// for now) the address is a website page explaining what to do. On the
  /// web there is no app, so the Site URL is used.
  static String? get passwordReset =>
      kIsWeb ? null : 'https://zerotrust.bz/auth/notes/';

  /// The confirm-email link lands on a website page that says the address is
  /// confirmed and to sign in here.
  static const confirmed = 'https://zerotrust.bz/auth/confirmed/';

  static StreamSubscription<Uri>? _links;
  static final _used = <String>{};

  /// Starts handling reset links. Call once, after Supabase.initialize.
  /// (Links that carry `?code=` instead, from the default email template,
  /// are handled by supabase_flutter itself.)
  static Future<void> listen() async {
    if (kIsWeb || _links != null) return;
    final appLinks = AppLinks();
    _links = appLinks.uriLinkStream.listen(_handle, onError: (_) {});
    try {
      final initial = await appLinks.getInitialLink();
      if (initial != null) await _handle(initial);
    } on Object catch (e) {
      debugPrint('Initial link unavailable: $e');
    }
  }

  static Future<void> _handle(Uri uri) async {
    if (uri.host != 'zerotrust.bz' || !uri.path.startsWith('/auth/')) return;
    // The token is after the # so it never reaches a web server.
    final params = Uri.splitQueryString(uri.fragment);
    final tokenHash = params['token_hash'];
    if (tokenHash == null || params['type'] != 'recovery') return;
    // The same link can arrive twice (initial link and stream); it works once.
    if (!_used.add(tokenHash)) return;
    try {
      // Signs in for recovery and raises AuthChangeEvent.passwordRecovery.
      await Supabase.instance.client.auth
          .verifyOTP(type: OtpType.recovery, tokenHash: tokenHash);
    } on Object catch (e) {
      // Expired or already used: the sign-in screen stays, and Forgot
      // password sends a new link.
      debugPrint('Password-reset link not accepted: $e');
    }
  }
}
