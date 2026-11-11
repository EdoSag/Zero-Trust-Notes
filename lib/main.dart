import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import 'l10n/l10n.dart';
import 'src/app/app_gate.dart';
import 'src/features/widgets/application/home_widget_sync_service.dart';
import 'src/features/widgets/presentation/widget_text_sync.dart';

const notesAppConfig = ZtAppConfig(
  appId: 'notes',
  displayName: 'Zero-Trust Notes',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    publishableKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  // The vault always cold-starts locked, but if the OS killed the previous
  // process before AppGate could clear them (a task kill rather than a
  // clean background pause), home-screen widget previews cached mid-session
  // would otherwise survive until the next lock. Unless the user chose
  // "Show details on the home screen", "locked" is the only state a widget
  // can show right after a cold start.
  await const HomeWidgetSyncService().clearUnlessAllowed();

  // English or Hebrew, as picked in Settings, from the first frame.
  await ZtLanguageController.preload();

  runApp(
    ProviderScope(
      overrides: [ztAppConfigProvider.overrideWithValue(notesAppConfig)],
      child: const ZeroTrustNotesApp(),
    ),
  );
}

class ZeroTrustNotesApp extends ConsumerWidget {
  const ZeroTrustNotesApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The suite's theme with Notes' accent, light/dark choice and
    // wallpaper colours, like the other Zero-Trust apps.
    return ZtThemeBuilder(
      builder: (context, theme, darkTheme, mode) => MaterialApp(
        title:
            'ZT Notes', // on-device task switcher label; store name stays Zero-Trust Notes
        theme: theme,
        darkTheme: darkTheme,
        themeMode: mode,
        // English (default) or Hebrew, from Settings → Appearance → Language.
        locale: ref.watch(ztLanguageProvider),
        supportedLocales: ZtLanguages.supported,
        localizationsDelegates: const [AppL10n.delegate, ...ZtLanguages.delegates],
        home: const AppGate(),
        builder: (context, child) =>
            AutoLockActivity(child: WidgetTextSync(child: child ?? const SizedBox.shrink())),
      ),
    );
  }
}
