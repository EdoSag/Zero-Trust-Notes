import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import 'src/app/app_gate.dart';
import 'src/features/widgets/application/home_widget_sync_service.dart';

const notesAppConfig = ZtAppConfig(appId: 'notes', displayName: 'Zero-Trust Notes');

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
  // would otherwise survive until the next lock. Clearing here means
  // "locked" is the only state a widget can show right after a cold start.
  await const HomeWidgetSyncService().clearAllPlaintext();

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
    return MaterialApp(
      title: notesAppConfig.displayName,
      theme: ZtTheme.light(),
      darkTheme: ZtTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      home: const AppGate(),
    );
  }
}
