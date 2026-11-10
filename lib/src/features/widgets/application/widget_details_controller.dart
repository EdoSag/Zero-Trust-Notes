import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../notes/application/notes_providers.dart';
import 'home_widget_sync_service.dart';

/// "Show details on the home screen": whether the Note widget may show note
/// text while Notes is in the background. Same switch, same words in every
/// Zero-Trust app. Off by default.
class WidgetDetailsController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => const HomeWidgetSyncService().detailsAllowed();

  Future<void> set(bool allowed) async {
    state = AsyncData(allowed);
    final notes = ref.read(notesListProvider).value;
    await const HomeWidgetSyncService().setDetailsAllowed(
      allowed,
      notes: notes,
    );
  }
}

final widgetDetailsProvider =
    AsyncNotifierProvider<WidgetDetailsController, bool>(
      WidgetDetailsController.new,
    );
