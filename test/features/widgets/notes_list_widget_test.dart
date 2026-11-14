import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_notes/l10n/generated/app_l10n.dart';
import 'package:zerotrust_notes/src/features/notes/domain/checklist_item.dart';
import 'package:zerotrust_notes/src/features/notes/domain/note.dart';
import 'package:zerotrust_notes/src/features/widgets/application/home_widget_sync_service.dart';
import 'package:zerotrust_notes/src/features/widgets/application/widget_launch_listener.dart';
import 'package:zerotrust_notes/src/features/widgets/domain/pending_widget_action.dart';

Note _note(
  String id, {
  String title = '',
  String body = '',
  int minute = 0,
  bool pinned = false,
  bool archived = false,
  bool trashed = false,
  bool locked = false,
  List<ChecklistItem>? checklist,
}) {
  final at = DateTime.utc(2026, 11, 14, 9, minute);
  return Note(
    id: id,
    notebookId: null,
    title: title,
    body: body,
    createdAt: at,
    updatedAt: at,
    pinned: pinned,
    archived: archived,
    trashedAt: trashed ? at : null,
    locked: locked,
    checklist: checklist,
  );
}

void main() {
  final en = lookupAppL10n(const Locale('en'));
  final he = lookupAppL10n(const Locale('he'));

  group('Notes list widget items', () {
    test('pinned first, then newest; archived and trashed left out', () {
      final items = HomeWidgetSyncService.notesListItems([
        _note('old', minute: 1),
        _note('new', minute: 5),
        _note('pin', minute: 0, pinned: true),
        _note('arch', minute: 9, archived: true),
        _note('bin', minute: 9, trashed: true),
      ], l: en);
      expect(items.map((i) => i['id']), ['pin', 'new', 'old']);
      expect(items.first['p'], isTrue);
      expect(items.last['p'], isFalse);
    });

    test('a locked note shows only its title, never its text', () {
      final items = HomeWidgetSyncService.notesListItems([
        _note('secret', title: 'Bank', body: 'PIN 1234', locked: true),
      ], l: en);
      expect(items.single['t'], 'Bank');
      expect(items.single['b'], 'Locked note');
      expect(items.toString(), isNot(contains('1234')));
    });

    test('a checklist lists open items before done ones', () {
      final items = HomeWidgetSyncService.notesListItems([
        _note(
          'list',
          title: 'Shopping',
          checklist: const [
            ChecklistItem(id: 'a', text: 'Milk', checked: true),
            ChecklistItem(id: 'b', text: 'Bread'),
          ],
        ),
      ], l: en);
      expect(items.single['b'], '☐ Bread\n☑ Milk');
    });

    test('long text is cut, and the list is capped', () {
      final items = HomeWidgetSyncService.notesListItems([
        for (var i = 0; i < 60; i++) _note('n$i', body: 'x' * 500, minute: i % 60),
      ], l: en);
      expect(items, hasLength(HomeWidgetSyncService.notesListMax));
      expect((items.first['b']! as String).length, 201);
    });

    test('Hebrew locked caption', () {
      final items = HomeWidgetSyncService.notesListItems([_note('s', locked: true)], l: he);
      expect(items.single['b'], he.lockedNote);
    });
  });

  group('Widget taps', () {
    PendingWidgetAction? action(String uri) => WidgetLaunchListener.widgetActionFor(Uri.parse(uri));

    test('quick capture buttons start the right kind of note', () {
      expect((action('zerotrustnotes://new-note')! as OpenNewNote).kind, NewNoteKind.text);
      expect((action('zerotrustnotes://new-note?kind=checklist')! as OpenNewNote).kind, NewNoteKind.checklist);
      expect((action('zerotrustnotes://new-note?kind=voice')! as OpenNewNote).kind, NewNoteKind.voice);
      expect((action('zerotrustnotes://new-note?kind=photo')! as OpenNewNote).kind, NewNoteKind.photo);
      expect((action('zerotrustnotes://new-note?kind=nonsense')! as OpenNewNote).kind, NewNoteKind.text);
    });

    test('a note row opens that note; the app icon just opens the app', () {
      expect((action('zerotrustnotes://note?id=abc')! as OpenNote).noteId, 'abc');
      expect(action('zerotrustnotes://open'), isNull);
    });
  });

  test('installed widgets match by short class name, as home_widget reports them', () {
    const list = HomeWidgetSyncService.notesListProviderQualifiedName;
    const single = HomeWidgetSyncService.singleNoteProviderQualifiedName;
    expect(HomeWidgetSyncService.sameProvider('.widgets.NotesListWidgetProvider', list), isTrue);
    expect(HomeWidgetSyncService.sameProvider(list, list), isTrue);
    expect(HomeWidgetSyncService.sameProvider('.widgets.NotesListWidgetProvider', single), isFalse);
    expect(HomeWidgetSyncService.sameProvider(null, list), isFalse);
  });
}
