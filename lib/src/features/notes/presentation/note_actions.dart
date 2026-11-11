import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../../reminders/reminder_scheduler.dart';
import '../../sharing/note_sharing.dart';
import '../application/note_lock.dart';
import '../application/notes_providers.dart';
import '../domain/note.dart';
import '../domain/note_color.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';

/// Pin, archive, colour, reminder, send, trash: the actions the list (long
/// press) and the editor share.
class NoteActions {
  NoteActions(this.context, this.ref);

  final BuildContext context;
  final WidgetRef ref;

  void _snack(String message, {VoidCallback? undo}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        // Flutter keeps a snackbar with an action open until it is tapped.
        persist: false,
        action: undo == null ? null : SnackBarAction(label: context.l10n.undo, onPressed: undo),
      ),
    );
  }

  Future<void> _save(Note note) async => ref.read(notesRepositoryProvider)?.updateNote(note);

  Future<Note> togglePin(Note note) async {
    // Pinning an archived note brings it back, like Keep.
    final updated = note.copyWith(pinned: !note.pinned, archived: false);
    await _save(updated);
    return updated;
  }

  Future<Note> toggleArchive(Note note, {bool showUndo = true}) async {
    final updated = note.copyWith(archived: !note.archived, pinned: false);
    await _save(updated);
    if (showUndo) {
      _snack(updated.archived ? currentL10n.noteArchived : currentL10n.noteUnarchived, undo: () => _save(note));
    }
    return updated;
  }

  Future<Note?> moveToTrash(Note note) async {
    final repository = ref.read(notesRepositoryProvider);
    if (repository == null) return null;
    final trashed = await repository.moveToTrash(note);
    _snack(currentL10n.noteTrashed, undo: () => _save(note));
    return trashed;
  }

  Future<Note?> restore(Note note) async {
    final restored = await ref.read(notesRepositoryProvider)?.restoreFromTrash(note);
    _snack(currentL10n.noteRestored);
    return restored;
  }

  Future<bool> deleteForever(Note note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.deleteForeverQ),
        content: Text(context.l10n.deleteForeverBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    await ref.read(notesRepositoryProvider)?.deleteNote(note);
    return true;
  }

  Future<Note?> pickColor(Note note) async {
    final color = await showNoteColorPicker(context, note.color);
    if (color == null || color == note.color) return null;
    final updated = note.copyWith(color: color);
    await _save(updated);
    return updated;
  }

  /// Returns the note with its new reminder (or none), or null if cancelled.
  Future<Note?> pickReminder(Note note) async {
    final choice = await showReminderPicker(context, ref, note.reminderAt);
    if (choice == null) return null;
    final updated = note.copyWith(reminderAt: choice.at);
    await _save(updated);
    return updated;
  }

  /// The long-press sheet in the list.
  Future<void> showSheet(Note note) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      // Taller than the default half screen, and scrolls in landscape.
      isScrollControlled: true,
      builder: (sheetContext) {
        Widget item(String value, IconData icon, String label) => ListTile(
          leading: Icon(icon),
          title: Text(label),
          onTap: () => Navigator.of(sheetContext).pop(value),
        );
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: note.isTrashed
                  ? [
                      item('restore', Icons.restore_from_trash_outlined, context.l10n.restore),
                      item('delete', Icons.delete_forever_outlined, context.l10n.deleteForever),
                    ]
                  : [
                      item(
                        'pin',
                        note.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                        note.pinned ? context.l10n.unpin : context.l10n.pin,
                      ),
                      item(
                        'archive',
                        note.archived ? Icons.unarchive_outlined : Icons.archive_outlined,
                        note.archived ? context.l10n.unarchive : context.l10n.archive,
                      ),
                      item('color', Icons.palette_outlined, context.l10n.colour),
                      item('reminder', Icons.notifications_none, context.l10n.remindMe),
                      item('send', Icons.share_outlined, context.l10n.send),
                      item('trash', Icons.delete_outline, context.l10n.moveToTrash),
                    ],
            ),
          ),
        );
      },
    );
    if (!context.mounted) return;
    switch (action) {
      case 'restore':
        await restore(note);
      case 'delete':
        await deleteForever(note);
      case 'pin':
        await togglePin(note);
      case 'archive':
        await toggleArchive(note);
      case 'color':
        await pickColor(note);
      case 'reminder':
        await pickReminder(note);
      case 'send':
        // A locked note's text leaves only after the owner confirms.
        if (note.locked &&
            !await ref
                .read(noteLockAuthenticatorProvider)
                .confirm(context, ref, reason: context.l10n.reasonSendLocked)) {
          return;
        }
        if (!context.mounted) return;
        await NoteSharing(context, ref).shareNote(note);
      case 'trash':
        await moveToTrash(note);
    }
  }
}

Future<NoteColor?> showNoteColorPicker(BuildContext context, NoteColor current) {
  return showModalBottomSheet<NoteColor>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final brightness = Theme.of(sheetContext).brightness;
      final scheme = Theme.of(sheetContext).colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final color in NoteColor.values)
                Semantics(
                  button: true,
                  selected: color == current,
                  label: color.displayName,
                  child: InkResponse(
                    onTap: () => Navigator.of(sheetContext).pop(color),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.background(brightness) ?? scheme.surface,
                        border: Border.all(
                          color: color == current ? scheme.primary : scheme.outlineVariant,
                          width: color == current ? 3 : 1,
                        ),
                      ),
                      child: color == NoteColor.none
                          ? Icon(Icons.format_color_reset_outlined, color: scheme.onSurfaceVariant)
                          : (color == current ? Icon(Icons.check, color: scheme.primary) : null),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// [at] is null when the user removed the reminder.
typedef ReminderChoice = ({DateTime? at});

/// Quick choices plus a date and time picker. Asks for notification
/// permission the first time a reminder is set.
Future<ReminderChoice?> showReminderPicker(
  BuildContext context,
  WidgetRef ref,
  DateTime? current,
) async {
  final now = DateTime.now();
  final laterToday = DateTime(now.year, now.month, now.day, 18);
  final tomorrow = DateTime(now.year, now.month, now.day + 1, 8);
  final nextWeek = DateTime(now.year, now.month, now.day + (8 - now.weekday), 8);
  final format = DateFormat('EEE d MMM, HH:mm');

  final picked = await showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (laterToday.isAfter(now.add(const Duration(minutes: 30))))
            ListTile(
              leading: const Icon(Icons.schedule),
              title: Text(context.l10n.laterToday),
              trailing: Text(DateFormat.Hm().format(laterToday)),
              onTap: () => Navigator.of(sheetContext).pop(laterToday),
            ),
          ListTile(
            leading: const Icon(Icons.wb_sunny_outlined),
            title: Text(context.l10n.tomorrowMorning),
            trailing: Text(format.format(tomorrow)),
            onTap: () => Navigator.of(sheetContext).pop(tomorrow),
          ),
          ListTile(
            leading: const Icon(Icons.date_range_outlined),
            title: Text(context.l10n.nextWeek),
            trailing: Text(format.format(nextWeek)),
            onTap: () => Navigator.of(sheetContext).pop(nextWeek),
          ),
          ListTile(
            leading: const Icon(Icons.edit_calendar_outlined),
            title: Text(context.l10n.pickDateTime),
            onTap: () => Navigator.of(sheetContext).pop('pick'),
          ),
          if (current != null)
            ListTile(
              leading: const Icon(Icons.notifications_off_outlined),
              title: Text(context.l10n.removeReminder),
              onTap: () => Navigator.of(sheetContext).pop('remove'),
            ),
        ],
      ),
    ),
  );
  if (picked == null || !context.mounted) return null;
  if (picked == 'remove') return (at: null);

  DateTime? at;
  if (picked is DateTime) {
    at = picked;
  } else {
    final initial = current != null && current.isAfter(now) ? current : tomorrow;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 10),
    );
    if (date == null || !context.mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !context.mounted) return null;
    at = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (!at.isAfter(DateTime.now())) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(context.l10n.pickFutureTime)));
      return null;
    }
  }

  final granted = await ref
      .read(vaultControllerProvider.notifier)
      .whileShowingSystemUi(() => ref.read(reminderSchedulerProvider).requestPermission());
  if (!granted && context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.reminderNotifsOff,
        ),
      ),
    );
  }
  return (at: at);
}

String formatReminder(DateTime at) {
  final now = DateTime.now();
  final local = at.toLocal();
  final time = DateFormat.Hm().format(local);
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return currentL10n.todayAt(time);
  if (diff == 1) return currentL10n.tomorrowAt(time);
  if (diff == -1) return currentL10n.yesterdayAt(time);
  if (local.year == now.year) return '${DateFormat('d MMM').format(local)}, $time';
  return '${DateFormat('d MMM y').format(local)}, $time';
}
