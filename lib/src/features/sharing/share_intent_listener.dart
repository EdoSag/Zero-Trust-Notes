import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/application/pending_widget_action_controller.dart';
import '../widgets/domain/pending_widget_action.dart';

/// Takes what other apps share to Notes (Android's share sheet; see
/// `ShareReceiverActivity`) and asks for a new note with it, which opens
/// once the vault is unlocked.
class ShareIntentListener {
  ShareIntentListener(this._ref);

  static const _channel = MethodChannel('dev.sagron.zerotrustnotes/share');

  final WidgetRef _ref;

  static bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> start() async {
    if (!isSupported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shareReceived') await _take();
    });
    await _take();
  }

  void dispose() {
    if (isSupported) _channel.setMethodCallHandler(null);
  }

  Future<void> _take() async {
    try {
      final share = await _channel.invokeMapMethod<Object?, Object?>('takeShare');
      if (share == null) return;
      _ref
          .read(pendingWidgetActionProvider.notifier)
          .set(CreateNoteFromShare(SharedContent.fromMap(share)));
    } on PlatformException {
      // Nothing shared, or an older native side.
    } on MissingPluginException {
      // Not running on the Android app (tests).
    }
  }
}
