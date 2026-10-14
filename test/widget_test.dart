import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/main.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-publishable-key',
    );
  });

  testWidgets('cold start with no session shows the sign-in screen', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [ztAppConfigProvider.overrideWithValue(notesAppConfig)],
      child: const ZeroTrustNotesApp(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Zero-Trust Notes'), findsOneWidget);
  });
}
