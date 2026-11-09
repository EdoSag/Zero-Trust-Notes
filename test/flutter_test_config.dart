import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests run as Android, where the app talks to `home_widget`'s native side.
/// Stand in for it with no widgets installed and nothing launched from one.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('home_widget'),
      (call) async => call.method == 'getInstalledWidgets' ? const <Object?>[] : null,
    );
    // Widget taps while running: none.
    messenger.setMockMethodCallHandler(
      const MethodChannel('home_widget/updates'),
      (call) async => null,
    );
  });
  await testMain();
}
