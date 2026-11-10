import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/src/features/notes/domain/note.dart';
import 'package:zerotrust_notes/src/features/notes/domain/notes_filter.dart';
import 'package:zerotrust_notes/src/features/notes/presentation/notes_list_page.dart';
import 'package:zerotrust_notes/src/shared/text_direction.dart';

Note note(String id, {double? position, int minute = 0, bool locked = false, String body = ''}) =>
    Note(
      id: id,
      notebookId: null,
      title: id,
      body: body,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026, 1, 1, 0, minute),
      position: position,
      locked: locked,
    );

/// As the list shows them in custom order.
List<Note> ordered(List<Note> notes) =>
    [...notes]..sort((a, b) => b.orderKey.compareTo(a.orderKey));

void main() {
  group('Note JSON', () {
    test('position and lock round-trip and are only written when set', () {
      final plain = Note.itemJson(title: 't', body: 'b', createdAt: DateTime.utc(2026));
      expect(plain.containsKey('position'), isFalse);
      expect(plain.containsKey('locked'), isFalse);

      final json = Note.itemJson(
        title: 't',
        body: 'b',
        createdAt: DateTime.utc(2026),
        position: 12.5,
        locked: true,
      );
      final read = Note.fromItem(LocalItem(itemId: 'n', json: json, updatedAt: DateTime.utc(2026)));
      expect(read.position, 12.5);
      expect(read.locked, isTrue);
      expect(read.extra, isEmpty);
    });

    test('a note never moved sorts by its last edit', () {
      final n = note('a', minute: 5);
      expect(n.orderKey, DateTime.utc(2026, 1, 1, 0, 5).millisecondsSinceEpoch);
    });
  });

  group('reorderPosition', () {
    final a = note('a', minute: 3);
    final b = note('b', minute: 2);
    final c = note('c', minute: 1);
    final section = ordered([a, b, c]);

    List<String> after(Note moved, Note target) {
      final position = reorderPosition(section, moved, target)!;
      return [
        for (final n in ordered([
          for (final n in section) n.id == moved.id ? n.copyWith(position: position) : n,
        ]))
          n.id,
      ];
    }

    test('moving down puts the note after the target', () {
      expect(after(a, b), ['b', 'a', 'c']);
      expect(after(a, c), ['b', 'c', 'a']);
    });

    test('moving up puts the note before the target', () {
      expect(after(c, a), ['c', 'a', 'b']);
      expect(after(c, b), ['a', 'c', 'b']);
    });

    test('dropping on itself changes nothing', () {
      expect(reorderPosition(section, b, b), isNull);
    });
  });

  test('a locked note is found by its title but not by its text', () {
    final notes = [note('Bank', locked: true, body: 'pin 1234'), note('Shop', body: 'milk')];
    expect(const NotesFilter(query: '1234').apply(notes).map((n) => n.id), isEmpty);
    expect(const NotesFilter(query: 'bank').apply(notes).map((n) => n.id), ['Bank']);
  });

  group('textDirectionOf', () {
    test('Hebrew reads right to left, English left to right', () {
      expect(textDirectionOf('שלום עולם'), TextDirection.rtl);
      expect(textDirectionOf('Hello שלום'), TextDirection.ltr);
      expect(textDirectionOf('12. קניות'), TextDirection.rtl);
    });

    test('no letters yet follows the app', () {
      expect(textDirectionOf(''), isNull);
      expect(textDirectionOf('123 !'), isNull);
    });
  });
}
