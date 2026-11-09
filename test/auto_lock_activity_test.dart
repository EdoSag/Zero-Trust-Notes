import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/src/app/app_gate.dart';

class _CountingVault extends VaultController {
  int touches = 0;
  @override
  VaultState build() => VaultLocked();
  @override
  void touch() => touches++;
}

void main() {
  testWidgets('touches on a pushed screen count as activity', (tester) async {
    final vault = _CountingVault();
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(ProviderScope(
      overrides: [vaultControllerProvider.overrideWith(() => vault)],
      child: MaterialApp(
        navigatorKey: nav,
        builder: (context, child) => AutoLockActivity(child: child!),
        home: const Text('home'),
      ),
    ));
    nav.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Center(child: Text('editor')))));
    await tester.pumpAndSettle();

    await tester.tap(find.text('editor'));
    expect(vault.touches, 1);
  });
}
