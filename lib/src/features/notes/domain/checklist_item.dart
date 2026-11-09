import 'package:uuid/uuid.dart';

/// One line of a checklist note.
class ChecklistItem {
  const ChecklistItem({required this.id, required this.text, this.checked = false});

  factory ChecklistItem.create(String text, {bool checked = false}) =>
      ChecklistItem(id: _uuid.v4(), text: text, checked: checked);

  factory ChecklistItem.fromJson(Map<String, Object?> json) => ChecklistItem(
    id: (json['id'] as String?) ?? _uuid.v4(),
    text: (json['text'] as String?) ?? '',
    checked: json['checked'] == true,
  );

  static const _uuid = Uuid();

  final String id;
  final String text;
  final bool checked;

  ChecklistItem copyWith({String? text, bool? checked}) =>
      ChecklistItem(id: id, text: text ?? this.text, checked: checked ?? this.checked);

  Map<String, Object?> toJson() => {'id': id, 'text': text, 'checked': checked};

  static final _taskLine = RegExp(r'^\s*(?:[-*+]\s+)?\[( |x|X)\]\s?(.*)$');
  static final _bullet = RegExp(r'^\s*[-*+]\s+(.*)$');

  /// One item per non-empty line. Markdown task lines (`- [x] milk`) keep
  /// their tick; plain bullets lose the bullet.
  static List<ChecklistItem> parseLines(String text) {
    final items = <ChecklistItem>[];
    for (final line in text.split('\n')) {
      if (line.trim().isEmpty) continue;
      final task = _taskLine.firstMatch(line);
      if (task != null) {
        items.add(ChecklistItem.create(task.group(2)!.trim(), checked: task.group(1) != ' '));
        continue;
      }
      final bullet = _bullet.firstMatch(line);
      items.add(ChecklistItem.create((bullet?.group(1) ?? line).trim()));
    }
    return items;
  }

  /// Unticked items first, then ticked ones, each keeping its order.
  static List<ChecklistItem> ordered(List<ChecklistItem> items) => [
    ...items.where((item) => !item.checked),
    ...items.where((item) => item.checked),
  ];

  static String toMarkdown(List<ChecklistItem> items) =>
      [for (final item in items) '- [${item.checked ? 'x' : ' '}] ${item.text}'].join('\n');
}
