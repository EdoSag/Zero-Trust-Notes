import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_notes/l10n/generated/app_l10n.dart';
import 'package:zerotrust_notes/src/features/notes/domain/checklist_item.dart';
import 'package:zerotrust_notes/src/features/notes/domain/note.dart';
import 'package:zerotrust_notes/src/features/widgets/application/checklist_widget_ticks.dart';
import 'package:zerotrust_notes/src/features/widgets/application/home_widget_sync_service.dart';

Note _list(String id, List<ChecklistItem> items, {bool locked = false, bool trashed = false}) {
  final at = DateTime.utc(2026, 11, 22, 9);
  return Note(
    id: id,
    notebookId: null,
    title: 'Shopping',
    body: ChecklistItem.toMarkdown(items),
    createdAt: at,
    updatedAt: at,
    checklist: items,
    locked: locked,
    trashedAt: trashed ? at : null,
  );
}

void main() {
  final en = lookupAppL10n(const Locale('en'));
  const milk = ChecklistItem(id: 'a', text: 'Milk');
  const bread = ChecklistItem(id: 'b', text: 'Bread');
  const eggs = ChecklistItem(id: 'c', text: 'Eggs', checked: true);

  group('Checklist widget items', () {
    test('lists open items first, with ids, text and ticks', () {
      final json = HomeWidgetSyncService.checklistItems(_list('n', [eggs, milk, bread]), l: en);
      expect(json['t'], 'Shopping');
      expect(json['i'], [
        {'id': 'a', 'x': 'Milk', 'c': false},
        {'id': 'b', 'x': 'Bread', 'c': false},
        {'id': 'c', 'x': 'Eggs', 'c': true},
      ]);
    });

    test('a locked note shows no items', () {
      final json = HomeWidgetSyncService.checklistItems(_list('n', [milk], locked: true), l: en);
      expect(json['t'], en.lockedNote);
      expect(json['i'], isEmpty);
    });
  });

  group('Queued widget ticks', () {
    test('parses the native queue and skips broken entries', () {
      final queue = jsonEncode([
        {'n': 'n', 'i': 'a', 'c': true, 'at': 1},
        {'n': 'n'},
        'junk',
        {'n': 'n', 'i': 'c', 'c': false, 'at': 2},
      ]);
      final ticks = ChecklistWidgetTick.parseQueue(queue);
      expect([for (final t in ticks) '${t.itemId}:${t.checked}'], ['a:true', 'c:false']);
      expect(ChecklistWidgetTick.parseQueue('not json'), isEmpty);
      expect(ChecklistWidgetTick.parseQueue(null), isEmpty);
    });

    test('applies the last tick per item and moves ticked items down', () {
      final note = _list('n', [milk, bread, eggs]);
      final changed = ChecklistWidgetTick.apply([note], const [
        ChecklistWidgetTick(noteId: 'n', itemId: 'a', checked: true),
        ChecklistWidgetTick(noteId: 'n', itemId: 'c', checked: false),
        ChecklistWidgetTick(noteId: 'n', itemId: 'b', checked: true),
        ChecklistWidgetTick(noteId: 'n', itemId: 'b', checked: false),
      ]);
      expect(changed, hasLength(1));
      final items = changed.single.checklist!;
      expect([for (final i in items) '${i.text}:${i.checked}'], [
        'Bread:false',
        'Eggs:false',
        'Milk:true',
      ]);
      expect(changed.single.body, '- [ ] Bread\n- [ ] Eggs\n- [x] Milk');
    });

    test('drops ticks for missing notes, items, trashed notes and no-ops', () {
      final note = _list('n', [milk]);
      expect(
        ChecklistWidgetTick.apply(
          [note, _list('t', [bread], trashed: true)],
          const [
            ChecklistWidgetTick(noteId: 'gone', itemId: 'a', checked: true),
            ChecklistWidgetTick(noteId: 'n', itemId: 'gone', checked: true),
            ChecklistWidgetTick(noteId: 'n', itemId: 'a', checked: false),
            ChecklistWidgetTick(noteId: 't', itemId: 'b', checked: true),
          ],
        ),
        isEmpty,
      );
    });
  });

  group('Saving widget ticks', () {
    test('ticks leave the queue only once every note is saved', () async {
      final queue = _FakeQueue(const [
        ChecklistWidgetTick(noteId: 'n', itemId: 'a', checked: true),
        ChecklistWidgetTick(noteId: 'm', itemId: 'b', checked: true),
      ]);
      final notes = [_list('n', [milk]), _list('m', [bread])];

      // The vault locks after the first save: nothing is dropped.
      var saves = 0;
      await expectLater(
        saveChecklistWidgetTicks(
          queue: queue,
          notes: notes,
          save: (note) async => ++saves == 1 ? note : throw StateError('locked'),
        ),
        throwsStateError,
      );
      expect(queue.acked, 0);

      // The next unlock applies the same queue again, and then drops it.
      final saved = <Note>[];
      final changed = await saveChecklistWidgetTicks(
        queue: queue,
        notes: notes,
        save: (note) async => note,
        onSaved: saved.add,
      );
      expect(changed, 2);
      expect(queue.acked, 2);
      expect(saved.map((n) => n.checklist!.single.checked), [true, true]);
    });

    test('an empty queue saves nothing', () async {
      final queue = _FakeQueue(const []);
      expect(
        await saveChecklistWidgetTicks(
          queue: queue,
          notes: const [],
          save: (_) => throw StateError('no save'),
        ),
        0,
      );
      expect(queue.acked, 0);
    });
  });
}

class _FakeQueue implements ChecklistWidgetTicks {
  _FakeQueue(this.ticks);

  final List<ChecklistWidgetTick> ticks;
  int acked = 0;

  @override
  Future<List<ChecklistWidgetTick>> peek() async => ticks;

  @override
  Future<void> ack(int count) async => acked += count;
}
