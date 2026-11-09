import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/pending_widget_action.dart';

final pendingWidgetActionProvider = NotifierProvider<PendingWidgetActionController, PendingWidgetAction?>(
  PendingWidgetActionController.new,
);

class PendingWidgetActionController extends Notifier<PendingWidgetAction?> {
  @override
  PendingWidgetAction? build() => null;

  void set(PendingWidgetAction action) => state = action;

  void clear() => state = null;
}
