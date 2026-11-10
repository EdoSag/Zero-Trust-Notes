import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../../notes/domain/note.dart';

/// Keeps the native Single Note widget's SharedPreferences-backed render
/// cache in sync with the vault's lock state.
///
/// Security invariant this service exists to enforce: `widget_<id>_title`
/// and `widget_<id>_body` are written **only** when the user turned on
/// "Show details on the home screen" ([setDetailsAllowed]), and only while
/// the vault is unlocked and the app is foreground ([writeUnlockedPreviews]).
/// With the switch off they are removed — not blanked — the instant the
/// vault locks or the app leaves the foreground ([clearUnlessAllowed]). With
/// it on they stay for the home screen until it is turned off or the account
/// signs out ([clearAllPlaintext]), like Tasks' and Calendar's widgets. `widget_<id>_note_id` is the one
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

  /// Every preview write and clear runs in this order, one at a time, so a
  /// slow write can't land after a clear and bring plaintext back.
  static Future<void> _queue = Future.value();

  /// Bumped by every [clearAllPlaintext]. A write started before the bump
  /// stops before writing anything more.
  static int _epoch = 0;

  static Future<void> _serialized(Future<void> Function() op) {
    final next = _queue.then((_) => op());
    _queue = next.catchError((Object _) {});
    return next;
  }

  /// "Show details on the home screen" (Settings), kept with the widget
  /// data so the cold-start clear in `main()` can read it before Riverpod.
  static const _detailsKey = 'notes_widget_details';

  /// Whether note text may stay on the home screen. Off by default.
  Future<bool> detailsAllowed() async {
    if (!isSupported) return false;
    try {
      return await HomeWidget.getWidgetData<bool>(_detailsKey) ?? false;
    } on Object {
      return false;
    }
  }

  /// Turns "Show details on the home screen" on or off. Off removes every
  /// preview at once; on shows [notes] (the unlocked notes) right away.
  Future<void> setDetailsAllowed(bool allowed, {List<Note>? notes}) async {
    if (!isSupported) return;
    await HomeWidget.saveWidgetData<bool>(_detailsKey, allowed);
    if (!allowed) return clearAllPlaintext();
    if (notes != null) return writeUnlockedPreviews(notes);
  }

  /// The vault locked or the app left the screen: removes the previews
  /// unless the user chose to keep note text on the home screen.
  Future<void> clearUnlessAllowed() async {
    if (await detailsAllowed()) return;
    return clearAllPlaintext();
  }

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
  Future<void> pinNote({required String appWidgetId, required Note note}) {
    final epoch = _epoch;
    return _serialized(() async {
      await HomeWidget.saveWidgetData<String>(_noteIdKey(appWidgetId), note.id);
      if (epoch != _epoch || !await detailsAllowed()) return _redraw();
      await _writePreview(appWidgetId, note);
      await HomeWidget.updateWidget(qualifiedAndroidName: singleNoteProviderQualifiedName);
    });
  }

  /// Re-resolves every pinned widget's note against the live [notes] list
  /// and refreshes its cached preview. Call whenever the vault unlocks, the
  /// notes list changes, or the app resumes to the foreground while
  /// unlocked — never while locked.
  Future<void> writeUnlockedPreviews(List<Note> notes) {
    final epoch = _epoch;
    return _serialized(() => _writeUnlockedPreviews(notes, epoch));
  }

  Future<void> _writeUnlockedPreviews(List<Note> notes, int epoch) async {
    if (epoch != _epoch || !await detailsAllowed()) return;
    final widgetIds = await _installedSingleNoteWidgetIds();
    if (widgetIds.isEmpty) return;

    final notesById = {for (final note in notes) note.id: note};
    for (final widgetId in widgetIds) {
      final appWidgetId = widgetId.toString();
      final noteId = await HomeWidget.getWidgetData<String>(_noteIdKey(appWidgetId));
      if (noteId == null) continue;
      // Cleared (lock or background) while this was running: stop.
      if (epoch != _epoch) return;
      final note = notesById[noteId];
      if (note == null) {
        await _writeMissingNotePlaceholder(appWidgetId);
      } else {
        await _writePreview(appWidgetId, note);
      }
    }
    await HomeWidget.updateWidget(qualifiedAndroidName: singleNoteProviderQualifiedName);
  }

  Future<void> _redraw() async {
    await HomeWidget.updateWidget(qualifiedAndroidName: singleNoteProviderQualifiedName);
  }

  Future<void> _writePreview(String appWidgetId, Note note) async {
    // A locked note shows only its title, here as in the list.
    final text = note.locked ? 'Locked note' : note.body;
    final body = text.length > _bodyPreviewLength ? '${text.substring(0, _bodyPreviewLength)}…' : text;
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
  /// locked: on sign-out and when "Show details on the home screen" is
  /// turned off. Lock, pause and cold start go through [clearUnlessAllowed].
  Future<void> clearAllPlaintext() {
    _epoch++;
    return _serialized(_clearAllPlaintext);
  }

  Future<void> _clearAllPlaintext() async {
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
