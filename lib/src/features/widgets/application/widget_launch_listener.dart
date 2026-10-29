import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../domain/pending_widget_action.dart';
import 'home_widget_sync_service.dart';
import 'pending_widget_action_controller.dart';

/// Bridges native widget taps into [pendingWidgetActionProvider].
///
/// Tap-to-launch (`zerotrustnotes://new-note`, `zerotrustnotes://note?id=…`)
/// is carried entirely by the `home_widget` plugin's own launch-intent
/// machinery, which already distinguishes cold start
/// ([HomeWidget.initiallyLaunchedFromHomeWidget]) from an already-running
/// app receiving a fresh tap ([HomeWidget.widgetClicked], driven by
/// `MainActivity`'s `onNewIntent`).
///
/// The widget *configuration* flow has no such stream in the plugin — only
/// a one-shot [HomeWidget.initiallyLaunchedFromHomeWidgetConfigure] check
/// against the activity's current intent — so a second configure request
/// arriving while the app is already warm is instead pushed from
/// `MainActivity.onNewIntent` over a small dedicated MethodChannel.
class WidgetLaunchListener {
  WidgetLaunchListener(this._ref);

  static const _configureChannel = MethodChannel('dev.sagron.zerotrustnotes/widget_configure');

  final WidgetRef _ref;
  StreamSubscription<Uri?>? _clickSubscription;

  Future<void> start() async {
    if (!HomeWidgetSyncService.isSupported) return;
    final configureId = await HomeWidget.initiallyLaunchedFromHomeWidgetConfigure();
    if (configureId != null) {
      _setConfigure(configureId);
      return;
    }

    _handleUri(await HomeWidget.initiallyLaunchedFromHomeWidget());
    _clickSubscription = HomeWidget.widgetClicked.listen(_handleUri);
    _configureChannel.setMethodCallHandler(_handleConfigureCall);
  }

  void dispose() {
    _clickSubscription?.cancel();
    _configureChannel.setMethodCallHandler(null);
  }

  Future<void> _handleConfigureCall(MethodCall call) async {
    if (call.method == 'configure') {
      _setConfigure(call.arguments as String);
    }
  }

  void _handleUri(Uri? uri) {
    if (uri == null) return;
    final action = switch (uri.host) {
      'new-note' => const OpenNewNote(),
      'note' when uri.queryParameters['id'] != null => OpenNote(uri.queryParameters['id']!),
      _ => null,
    };
    if (action != null) {
      _ref.read(pendingWidgetActionProvider.notifier).set(action);
    }
  }

  void _setConfigure(String appWidgetId) {
    _ref.read(pendingWidgetActionProvider.notifier).set(ConfigureNoteWidget(appWidgetId));
  }
}
