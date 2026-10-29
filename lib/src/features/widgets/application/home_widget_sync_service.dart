import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../../notes/domain/note.dart';

/// Keeps the native Single Note widget's SharedPreferences-backed render
/// cache in sync with the vault's lock state.
///
/// Security invariant this service exists to enforce: `widget_<id>_title`
/// and `widget_<id>_body` are written **only** while the vault is unlocked
/// and the app is foreground ([writeUnlockedPreviews]), and are removed —
/// not blanked — the instant the vault locks or the app leaves the
/// foreground ([clearAllPlaintext]). `widget_<id>_note_id` is the one
/// exception: it is not secret (same trust tier as the store's own item
/// ids) and is left in place so the widget remembers which note it's pinned
/// to across a lock/unlock cycle.
///
/// Home-screen widgets exist only on Android; elsewhere every call is a
/// no-op.
class HomeWidgetSyncService {
  const HomeWidgetSyncService();

  static bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static const singleNoteProviderQualifiedName = 'dev.sagron.zerotrustnotes.widgets.SingleNoteWidgetProvider';

  static const _bodyPreviewLength = 200;

  String _noteIdKey(String appWidgetId) => 'widget_${appWidgetId}_note_id';
  String _lockedKey(String appWidgetId) => 'widget_${appWidgetId}_locked';
  String _titleKey(String appWidgetId) => 'widget_${appWidgetId}_title';
  String _bodyKey(String appWidgetId) => 'widget_${appWidgetId}_body';

  Future<List<int>> _installedSingleNoteWidgetIds() async {
    if (!isSupported) return const [];
    final installed = await HomeWidget.getInstalledWidgets();
    return installed
        .where((info) => info.androidClassName == singleNoteProviderQualifiedName)
        .map((info) => info.androidWidgetId)
        .whereType<int>()
        .toList();
  }

  /// Pins [note] to [appWidgetId] and immediately shows its preview. Called
  /// only from the note picker, which is itself only reachable once the
  /// vault is unlocked.
  Future<void> pinNote({required String appWidgetId, required Note note}) async {
    await HomeWidget.saveWidgetData<String>(_noteIdKey(appWidgetId), note.id);
    await _writePreview(appWidgetId, note);
    await HomeWidget.updateWidget(qualifiedAndroidName: singleNoteProviderQualifiedName);
  }

  /// Re-resolves every pinned widget's note against the live [notes] list
  /// and refreshes its cached preview. Call whenever the vault unlocks, the
  /// notes list changes, or the app resumes to the foreground while
  /// unlocked — never while locked.
  Future<void> writeUnlockedPreviews(List<Note> notes) async {
    final widgetIds = await _installedSingleNoteWidgetIds();
    if (widgetIds.isEmpty) return;

    final notesById = {for (final note in notes) note.id: note};
    for (final widgetId in widgetIds) {
      final appWidgetId = widgetId.toString();
      final noteId = await HomeWidget.getWidgetData<String>(_noteIdKey(appWidgetId));
      if (noteId == null) continue;
      final note = notesById[noteId];
      if (note == null) {
        await _writeMissingNotePlaceholder(appWidgetId);
      } else {
        await _writePreview(appWidgetId, note);
      }
    }
    await HomeWidget.updateWidget(qualifiedAndroidName: singleNoteProviderQualifiedName);
  }

  Future<void> _writePreview(String appWidgetId, Note note) async {
    final body = note.body.length > _bodyPreviewLength ? '${note.body.substring(0, _bodyPreviewLength)}…' : note.body;
    await HomeWidget.saveWidgetData<bool>(_lockedKey(appWidgetId), false);
    await HomeWidget.saveWidgetData<String>(_titleKey(appWidgetId), note.title.isEmpty ? '(untitled)' : note.title);
    await HomeWidget.saveWidgetData<String>(_bodyKey(appWidgetId), body);
  }

  Future<void> _writeMissingNotePlaceholder(String appWidgetId) async {
    await HomeWidget.saveWidgetData<bool>(_lockedKey(appWidgetId), false);
    await HomeWidget.saveWidgetData<String>(_titleKey(appWidgetId), 'Note deleted');
    await HomeWidget.saveWidgetData<String>(_bodyKey(appWidgetId), '');
  }

  /// Removes every cached title/body preview and marks all pinned widgets
  /// locked. `AppGate` calls this whenever the vault locks or the app is
  /// paused, and `main()` on every cold start.
  Future<void> clearAllPlaintext() async {
    final widgetIds = await _installedSingleNoteWidgetIds();
    for (final widgetId in widgetIds) {
      final appWidgetId = widgetId.toString();
      await HomeWidget.saveWidgetData<bool>(_lockedKey(appWidgetId), true);
      await HomeWidget.saveWidgetData<String>(_titleKey(appWidgetId), null);
      await HomeWidget.saveWidgetData<String>(_bodyKey(appWidgetId), null);
    }
    if (widgetIds.isNotEmpty) {
      await HomeWidget.updateWidget(qualifiedAndroidName: singleNoteProviderQualifiedName);
    }
  }
}
