// Draws the launcher icons (Android, iOS, web) from the suite's brand mark,
// the same one on the sign-in screen and in "Other Zero-Trust apps".
// Run it again when the mark changes:
//   flutter test tool/launcher_icon_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

void main() {
  testWidgets('launcher icons', (tester) async {
    await tester.runAsync(() => ZtLauncherIcons.write(ZtSuite.notes));
  });
}
