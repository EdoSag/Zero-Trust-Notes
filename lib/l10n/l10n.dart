import 'package:flutter/widgets.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import 'generated/app_l10n.dart';

export 'generated/app_l10n.dart';

/// ZT Notes's own strings, in English and Hebrew (`app_en.arb`,
/// `app_he.arb`). The language is the one picked under Settings →
/// Appearance → Language (`ztLanguageProvider` in the core).
extension AppL10nContext on BuildContext {
  AppL10n get l10n => AppL10n.of(this);
}

/// The strings for the app's current language, for code without a
/// [BuildContext] (notifications, the home screen widget, exports).
AppL10n get currentL10n {
  final code = ZtL10n.current.localeName.split('_').first;
  return lookupAppL10n(
    AppL10n.supportedLocales.any((l) => l.languageCode == code)
        ? Locale(code)
        : const Locale('en'),
  );
}
