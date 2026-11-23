import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../notes/domain/checklist_item.dart';
import '../../notes/domain/note.dart';
import 'home_widget_sync_service.dart';

/// One tick (or untick) made on a Checklist widget while Notes was closed
/// or locked: which item of which note, and whether it is now ticked.
class ChecklistWidgetTick {
  const ChecklistWidgetTick({required this.noteId, required this.itemId, required this.checked});

  final String noteId;
  final String itemId;
  final bool checked;

  /// The queue the widget keeps (`ChecklistTicks.kt`), oldest first. An
  /// entry this build can't read is skipped.
  static List<ChecklistWidgetTick> parseQueue(String? json) {
    if (json == null || json.isEmpty) return const [];
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      return const [];
    }
    if (decoded is! List) return const [];
    return [
      for (final entry in decoded)
        if (entry is Map && entry['n'] is String && entry['i'] is String)
          ChecklistWidgetTick(
            noteId: entry['n'] as String,
            itemId: entry['i'] as String,
            checked: entry['c'] == true,
          ),
    ];
  }

  /// The notes of [notes] that [ticks] change, as they should now be
  /// saved: each item set to its last tick, ticked items moved below open
  /// ones like a tick in the app does. Ticks for notes or items that are
  /// gone (deleted, or no longer a checklist) are dropped.
  static List<Note> apply(List<Note> notes, List<ChecklistWidgetTick> ticks) {
    final byId = {for (final note in notes) note.id: note};
    final latest = <String, Map<String, bool>>{};
    for (final tick in ticks) {
      (latest[tick.noteId] ??= {})[tick.itemId] = tick.checked;
    }
    final changed = <Note>[];
    for (final MapEntry(key: noteId, value: states) in latest.entries) {
      final note = byId[noteId];
      final items = note?.checklist;
      if (note == null || items == null || note.isTrashed) continue;
      var any = false;
      final updated = <ChecklistItem>[];
      for (final item in items) {
        final checked = states[item.id];
        if (checked == null || checked == item.checked) {
          updated.add(item);
        } else {
          any = true;
          updated.add(item.copyWith(checked: checked));
        }
      }
      if (any) changed.add(note.withChecklist(updated));
    }
    return changed;
  }
}

/// The Checklist widgets' queued ticks on Android. Reading leaves them
/// queued; [ack] drops them once they are saved, so ticks are never lost
/// to a save that fails part-way.
class ChecklistWidgetTicks {
  const ChecklistWidgetTicks();

  static const _channel = MethodChannel('dev.sagron.zerotrustnotes/checklist_widget');

  Future<List<ChecklistWidgetTick>> peek() async {
    if (!HomeWidgetSyncService.isSupported) return const [];
    try {
      return ChecklistWidgetTick.parseQueue(await _channel.invokeMethod<String>('peekTicks'));
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  /// Drops the first [count] queued ticks. Ticks made since [peek] stay.
  Future<void> ack(int count) async {
    if (!HomeWidgetSyncService.isSupported || count <= 0) return;
    try {
      await _channel.invokeMethod<void>('ackTicks', {'count': count});
    } on MissingPluginException {
      // Nothing queued here.
    } on PlatformException {
      // Left queued: applying them again changes nothing.
    }
  }
}

/// Saves the queued widget ticks into [notes] with [save], one note at a
/// time, then drops them from the queue. If a save throws (the vault
/// locking part-way), nothing is dropped and the error goes to the caller:
/// the next unlock applies the queue again, and a tick sets an item's
/// state, so applying it twice is harmless. [onSaved] gets each note as
/// saved. Returns how many notes changed.
Future<int> saveChecklistWidgetTicks({
  required ChecklistWidgetTicks queue,
  required List<Note> notes,
  required Future<Note> Function(Note note) save,
  void Function(Note saved)? onSaved,
}) async {
  final ticks = await queue.peek();
  if (ticks.isEmpty) return 0;
  final changed = ChecklistWidgetTick.apply(notes, ticks);
  for (final note in changed) {
    final saved = await save(note);
    onSaved?.call(saved);
  }
  await queue.ack(ticks.length);
  return changed.length;
}

final checklistWidgetTicksProvider = Provider<ChecklistWidgetTicks>(
  (ref) => const ChecklistWidgetTicks(),
);

/// The last note that widget ticks were saved into, so an editor that has
/// it open takes the ticks instead of saving over them.
final widgetTickedNoteProvider = NotifierProvider<WidgetTickedNote, Note?>(WidgetTickedNote.new);

class WidgetTickedNote extends Notifier<Note?> {
  @override
  Note? build() => null;

  void saved(Note note) => state = note;
}
