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
}
