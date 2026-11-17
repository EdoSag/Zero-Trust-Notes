import 'package:flutter/foundation.dart' show kIsWeb;

/// Where the links in account emails lead. Both addresses must be allowed in
/// Supabase (Authentication > URL Configuration > Redirect URLs:
/// https://zerotrust.bz/auth/**), or Supabase sends people to the Site URL.
abstract final class EmailLinks {
  /// The password-reset link opens this app: Android App Links, via the
  /// intent filter for https://zerotrust.bz/auth/notes/ in AndroidManifest.xml
  /// and the website's /.well-known/assetlinks.json. supabase_flutter turns
  /// the link into the password-recovery sign-in and AppGate shows
  /// ZtResetPasswordScreen. Where the app can't open it (the web, iOS for
  /// now), that address is a website page explaining what to do; on the web
  /// there is no app at all, so the Site URL is used.
  static String? get passwordReset =>
      kIsWeb ? null : 'https://zerotrust.bz/auth/notes/';

  /// The confirm-email link lands on a website page that says the address is
  /// confirmed and to sign in here.
  static const confirmed = 'https://zerotrust.bz/auth/confirmed/';
}
