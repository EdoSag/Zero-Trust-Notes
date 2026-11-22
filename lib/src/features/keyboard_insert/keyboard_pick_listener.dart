import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/application/pending_widget_action_controller.dart';
import '../widgets/domain/pending_widget_action.dart';

/// ZT Keyboard's "Insert from ZT apps" key opens Notes so the user can pick
/// a line of a note to type. The Android side has already checked that the
/// asking app is signed with this app's own key (see `TextPick.kt`); this
/// asks for the pick screen, which opens once the vault is unlocked.
class KeyboardPickListener {
  KeyboardPickListener(this._ref);

  static const _channel = MethodChannel('dev.sagron.zerotrustnotes/text_pick');

  final WidgetRef _ref;

  static bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> start() async {
    if (!isSupported) return;
    try {
      if (await _channel.invokeMethod<bool>('isPick') == true) {
        _ref.read(pendingWidgetActionProvider.notifier).set(const PickTextForKeyboard());
      }
    } on PlatformException {
      // An older native side.
    } on MissingPluginException {
      // Not running on the Android app (tests).
    }
  }

  /// Answers the keyboard with the picked [text] (null: nothing) and closes
  /// the pick screen.
  static Future<void> finish(String? text) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('finish', {'text': text});
    } on PlatformException {
      // Nothing to answer.
    } on MissingPluginException {
      // Not running on the Android app (tests).
    }
  }
}
