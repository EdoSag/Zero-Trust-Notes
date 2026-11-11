import '../../notebooks/domain/notebook.dart';
import '../../tags/domain/tag.dart';
import 'note.dart';
import 'note_color.dart';

/// The list a user is looking at, like Keep's side menu.
enum NotesView { notes, reminders, archive, trash }

/// Search text plus the filters a search can be narrowed by.
class NotesFilter {
  const NotesFilter({
    this.view = NotesView.notes,
    this.query = '',
    this.notebookId,
    this.unfiledOnly = false,
    this.tagId,
    this.color,
    this.checklistsOnly = false,
    this.withReminderOnly = false,
  });

  final NotesView view;
  final String query;
  final String? notebookId;
  final bool unfiledOnly;
  final String? tagId;
  final NoteColor? color;
  final bool checklistsOnly;
  final bool withReminderOnly;

  /// Anything beyond the view itself narrows the list.
  bool get isFiltering =>
      query.trim().isNotEmpty ||
      notebookId != null ||
      unfiledOnly ||
      tagId != null ||
      color != null ||
      checklistsOnly ||
      withReminderOnly;

  static const _unset = Object();

  NotesFilter copyWith({
    NotesView? view,
    String? query,
    Object? notebookId = _unset,
    bool? unfiledOnly,
    Object? tagId = _unset,
    Object? color = _unset,
    bool? checklistsOnly,
    bool? withReminderOnly,
  }) => NotesFilter(
    view: view ?? this.view,
    query: query ?? this.query,
    notebookId: identical(notebookId, _unset) ? this.notebookId : notebookId as String?,
    unfiledOnly: unfiledOnly ?? this.unfiledOnly,
    tagId: identical(tagId, _unset) ? this.tagId : tagId as String?,
    color: identical(color, _unset) ? this.color : color as NoteColor?,
    checklistsOnly: checklistsOnly ?? this.checklistsOnly,
    withReminderOnly: withReminderOnly ?? this.withReminderOnly,
  );

  /// Keeps the view, drops every search filter.
  NotesFilter cleared() => NotesFilter(view: view);

  bool _inView(Note note) => switch (view) {
    NotesView.notes => !note.isTrashed && !note.archived,
    NotesView.reminders => !note.isTrashed && note.hasAnyReminder,
    NotesView.archive => !note.isTrashed && note.archived,
    NotesView.trash => note.isTrashed,
  };

  /// [notes] in this view that match, in display order.
  ///
  /// The search text matches title, text (checklist items included), and
  /// the names of the note's tags and notebook.
  List<Note> apply(
    List<Note> notes, {
    List<Tag> tags = const [],
    List<Notebook> notebooks = const [],
  }) {
    final tagNames = {for (final tag in tags) tag.id: tag.name.toLowerCase()};
    final notebookNames = {
      for (final notebook in notebooks) notebook.id: notebook.name.toLowerCase(),
    };
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

    bool matchesQuery(Note note) {
      if (words.isEmpty) return true;
      final haystack = [
        note.title.toLowerCase(),
        // A locked note's text stays hidden until it's opened.
        if (!note.locked) note.body.toLowerCase(),
        for (final id in note.tagIds) ?tagNames[id],
        if (note.notebookId != null) ?notebookNames[note.notebookId],
      ].join('\n');
      return words.every(haystack.contains);
    }

    final result = notes.where((note) {
      if (!_inView(note)) return false;
      if (unfiledOnly && note.notebookId != null && notebookNames.containsKey(note.notebookId)) {
        return false;
      }
      if (notebookId != null && note.notebookId != notebookId) return false;
      if (tagId != null && !note.tagIds.contains(tagId)) return false;
      if (color != null && note.color != color) return false;
      if (checklistsOnly && !note.isChecklist) return false;
      if (withReminderOnly && !note.hasAnyReminder) return false;
      return matchesQuery(note);
    }).toList();

    switch (view) {
      case NotesView.reminders:
        // Timed reminders by time, then place reminders (no time) by title.
        result.sort((a, b) {
          final at = a.reminderAt, bt = b.reminderAt;
          if (at != null && bt != null) return at.compareTo(bt);
          if (at != null) return -1;
          if (bt != null) return 1;
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
      case NotesView.trash:
        result.sort((a, b) => b.trashedAt!.compareTo(a.trashedAt!));
      case NotesView.notes || NotesView.archive:
        break; // The caller's sort order, pinned first (see [pinnedFirst]).
    }
    return result;
  }

  /// Splits [notes] into pinned and the rest, keeping order. Only the main
  /// Notes view shows pins.
  ({List<Note> pinned, List<Note> others}) pinnedFirst(List<Note> notes) {
    if (view != NotesView.notes) return (pinned: const [], others: notes);
    return (
      pinned: [
        for (final note in notes)
          if (note.pinned) note,
      ],
      others: [
        for (final note in notes)
          if (!note.pinned) note,
      ],
    );
  }
}
