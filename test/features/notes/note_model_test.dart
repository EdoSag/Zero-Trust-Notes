import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/src/features/notebooks/domain/notebook.dart';
import 'package:zerotrust_notes/src/features/notes/domain/checklist_item.dart';
import 'package:zerotrust_notes/src/features/notes/domain/note.dart';
import 'package:zerotrust_notes/src/features/notes/domain/note_color.dart';
import 'package:zerotrust_notes/src/features/notes/domain/notes_filter.dart';
import 'package:zerotrust_notes/src/features/reminders/reminder_scheduler.dart';
import 'package:zerotrust_notes/src/features/tags/domain/tag.dart';

Note note(
  String id, {
  String title = '',
  String body = '',
  bool pinned = false,
  bool archived = false,
  DateTime? trashedAt,
  NoteColor color = NoteColor.none,
  List<ChecklistItem>? checklist,
  DateTime? reminderAt,
  List<String> tagIds = const [],
  String? notebookId,
}) => Note(
  id: id,
  notebookId: notebookId,
  title: title,
  body: body,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  tagIds: tagIds,
  pinned: pinned,
  archived: archived,
  trashedAt: trashedAt,
  color: color,
  checklist: checklist,
  reminderAt: reminderAt,
);

void main() {
  group('Note item JSON', () {
    test('a note written by an older Notes build reads as a plain text note', () {
      final old = Note.fromItem(
        LocalItem(
          itemId: 'a',
          updatedAt: DateTime.utc(2026, 1, 2),
          json: {
            'title': 'Old',
            'body': 'text',
            'notebookId': null,
            'tagIds': <String>[],
            'createdAt': '2026-01-01T00:00:00.000Z',
          },
        ),
      );
      expect(old.pinned, isFalse);
      expect(old.archived, isFalse);
      expect(old.isTrashed, isFalse);
      expect(old.isChecklist, isFalse);
      expect(old.color, NoteColor.none);
      expect(old.reminderAt, isNull);
      // Saving it again writes exactly the keys older builds wrote.
      expect(old.toItemJson().keys.toSet(), {'title', 'body', 'notebookId', 'tagIds', 'createdAt'});
    });

    test('new fields round-trip, and unknown keys from newer builds are kept', () {
      final original = note(
        'a',
        title: 'Shop',
        pinned: true,
        archived: true,
        color: NoteColor.teal,
        trashedAt: DateTime.utc(2026, 3),
        reminderAt: DateTime.utc(2026, 4, 1, 9),
      ).withChecklist([ChecklistItem.create('milk', checked: true), ChecklistItem.create('eggs')]);
      final json = {...original.toItemJson(), 'futureField': 42};
      final read = Note.fromItem(LocalItem(itemId: 'a', updatedAt: DateTime.utc(2026), json: json));

      expect(read.pinned, isTrue);
      expect(read.archived, isTrue);
      expect(read.color, NoteColor.teal);
      expect(read.trashedAt, DateTime.utc(2026, 3));
      expect(read.reminderAt, DateTime.utc(2026, 4, 1, 9));
      expect([for (final i in read.checklist!) (i.text, i.checked)], [('eggs', false), ('milk', true)]);
      expect(read.body, '- [ ] eggs\n- [x] milk');
      expect(read.toItemJson()['futureField'], 42);
    });

    test('a text note turns into a checklist and back', () {
      final text = note('a', body: '- [x] milk\n* eggs\n\nbread');
      final list = text.toggledChecklist();
      expect([for (final i in list.checklist!) (i.text, i.checked)], [
        ('milk', true),
        ('eggs', false),
        ('bread', false),
      ]);
      final back = list.toggledChecklist();
      expect(back.isChecklist, isFalse);
      expect(back.body, 'milk\neggs\nbread');
    });

    test('Note.withChecklist moves ticked items below unticked ones', () {
      final items = [
        ChecklistItem.create('a', checked: true),
        ChecklistItem.create('b'),
        ChecklistItem.create('c', checked: true),
        ChecklistItem.create('d'),
      ];
      expect([for (final i in note('x').withChecklist(items).checklist!) i.text], ['b', 'd', 'a', 'c']);
    });
  });

  group('NotesFilter', () {
    final work = Notebook(id: 'nb', name: 'Work');
    final urgent = const Tag(id: 't', name: 'Urgent');
    final notes = [
      note('plain', title: 'Groceries', body: 'apples'),
      note('pinned', title: 'Pinned', pinned: true),
      note('archived', title: 'Old trip', archived: true),
      note('trashed', title: 'Gone', trashedAt: DateTime.utc(2026)),
      note('tagged', title: 'Report', tagIds: ['t'], notebookId: 'nb', color: NoteColor.red),
      note(
        'list',
        title: 'Packing',
        checklist: [ChecklistItem.create('passport')],
        body: '- [ ] passport',
        reminderAt: DateTime.utc(2030),
      ),
    ];

    List<String> ids(NotesFilter filter) =>
        [for (final n in filter.apply(notes, tags: [urgent], notebooks: [work])) n.id];

    test('each view shows its notes and Trash is kept out of the others', () {
      expect(ids(const NotesFilter()), ['plain', 'pinned', 'tagged', 'list']);
      expect(ids(const NotesFilter(view: NotesView.archive)), ['archived']);
      expect(ids(const NotesFilter(view: NotesView.trash)), ['trashed']);
      expect(ids(const NotesFilter(view: NotesView.reminders)), ['list']);
    });

    test('search matches text, checklist items, tag and notebook names', () {
      expect(ids(const NotesFilter(query: 'apples')), ['plain']);
      expect(ids(const NotesFilter(query: 'PASSPORT')), ['list']);
      expect(ids(const NotesFilter(query: 'urgent')), ['tagged']);
      expect(ids(const NotesFilter(query: 'work report')), ['tagged']);
      expect(ids(const NotesFilter(query: 'gone')), isEmpty);
    });

    test('filters by colour, type, reminder, tag, notebook and unfiled', () {
      expect(ids(const NotesFilter(color: NoteColor.red)), ['tagged']);
      expect(ids(const NotesFilter(checklistsOnly: true)), ['list']);
      expect(ids(const NotesFilter(withReminderOnly: true)), ['list']);
      expect(ids(const NotesFilter(tagId: 't')), ['tagged']);
      expect(ids(const NotesFilter(notebookId: 'nb')), ['tagged']);
      expect(ids(const NotesFilter(unfiledOnly: true)), ['plain', 'pinned', 'list']);
    });

    test('pinned notes come first in the Notes view only', () {
      const filter = NotesFilter();
      final sections = filter.pinnedFirst(filter.apply(notes));
      expect([for (final n in sections.pinned) n.id], ['pinned']);
      expect(sections.others, hasLength(3));
    });
  });

  group('reminders', () {
    test('only future reminders outside Trash are scheduled', () {
      final now = DateTime.utc(2026, 6);
      final reminders = ScheduledReminder.fromNotes([
        note('future', title: 'Call', reminderAt: DateTime.utc(2026, 7)),
        note('past', reminderAt: DateTime.utc(2026, 5)),
        note('trashed', reminderAt: DateTime.utc(2026, 7), trashedAt: now),
        note('none'),
      ], now);
      expect([for (final r in reminders) r.noteId], ['future']);
      expect(reminders.single.title, 'Call');
    });

    test('notification ids are stable and payloads lead back to the note', () {
      expect(
        ScheduledReminder.notificationIdFor('abc'),
        ScheduledReminder.notificationIdFor('abc'),
      );
      expect(ScheduledReminder.notificationIdFor('abc'), isNot(ScheduledReminder.notificationIdFor('abd')));
      expect(ScheduledReminder.notificationIdFor('x'), inInclusiveRange(0, 0x7fffffff));
      final reminder = ScheduledReminder(noteId: 'n1', at: DateTime.utc(2027), title: 't');
      expect(ScheduledReminder.noteIdFromPayload(reminder.payload), 'n1');
    });
  });
}
