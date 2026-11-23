import 'dart:typed_data';

import '../notes/domain/checklist_item.dart';

/// A note read from another app's export, before it is saved (N-1).
class ImportedNote {
  const ImportedNote({
    required this.title,
    required this.body,
    this.tags = const [],
    this.notebook,
    this.createdAt,
    this.pinned = false,
    this.archived = false,
    this.trashed = false,
    this.checklist,
    this.files = const [],
  });

  final String title;

  /// Markdown, as Notes stores it.
  final String body;
  final List<String> tags;
  final String? notebook;
  final DateTime? createdAt;
  final bool pinned;
  final bool archived;
  final bool trashed;
  final List<ChecklistItem>? checklist;

  /// Pictures and other files that came with the note.
  final List<ImportedFile> files;

  bool get isEmpty => title.trim().isEmpty && body.trim().isEmpty && files.isEmpty;
}

class ImportedFile {
  const ImportedFile({required this.name, required this.bytes, this.mimeType});

  final String name;
  final String? mimeType;
  final Uint8List bytes;

  bool get isImage => mimeType?.startsWith('image/') ?? false;
}

/// A checklist when every line of [body] is a task line (`[ ] milk`,
/// `- [x] bread`), else null: Evernote and Apple Notes to-do lists become
/// Notes checklists.
List<ChecklistItem>? checklistOf(String body) {
  final lines = [
    for (final line in body.split('\n'))
      if (line.trim().isNotEmpty) line,
  ];
  final task = RegExp(r'^\s*(?:[-*+]\s+)?\[( |x|X)\]\s');
  if (lines.isEmpty || !lines.every(task.hasMatch)) return null;
  return ChecklistItem.parseLines(body);
}

/// HTML (Evernote, Apple Notes, exported web pages) as Markdown-like text:
/// paragraphs and line breaks kept, lists as `- `, to-dos as `[ ]` and
/// `[x]`, links as `[text](url)`, pictures as `![](src)`, everything else
/// as plain text.
String htmlToText(String html) {
  var s = html;
  RegExp re(String pattern) => RegExp(pattern, caseSensitive: false, dotAll: true);
  s = s.replaceAll(re(r'<!--.*?-->'), '');
  s = s.replaceAll(re(r'<(script|style|head|title)\b[^>]*>.*?</\1\s*>'), '');
  bool checked(String attributes) =>
      re(r'''checked\s*=\s*["']?(true|checked)|\bchecked\b(?!\s*=)''').hasMatch(attributes);
  s = s.replaceAllMapped(
    re(r'<en-todo\b([^>]*?)/?>(\s*</en-todo>)?\s*'),
    (m) => checked(m[1]!) ? '[x] ' : '[ ] ',
  );
  s = s.replaceAllMapped(
    re(r'''<input\b([^>]*\btype\s*=\s*["']?checkbox[^>]*)>\s*'''),
    (m) => checked(m[1]!) ? '[x] ' : '[ ] ',
  );
  s = s.replaceAll(re(r'<en-media\b[^>]*?/?>(\s*</en-media>)?'), '');
  s = s.replaceAllMapped(
    re(r'''<img\b[^>]*?\bsrc\s*=\s*["']([^"']+)["'][^>]*>'''),
    (m) => '\n![](${m[1]})\n',
  );
  s = s.replaceAllMapped(re(r'''<a\b[^>]*?\bhref\s*=\s*["']([^"']*)["'][^>]*>(.*?)</a\s*>'''), (m) {
    final href = _entities(m[1]!.trim());
    final text = _entities(m[2]!.replaceAll(re(r'<[^>]+>'), '')).trim();
    if (href.isEmpty || href.startsWith('#')) return text;
    return text.isEmpty || text == href ? href : '[$text]($href)';
  });
  s = s.replaceAllMapped(re(r'<h([1-6])\b[^>]*>'), (m) => '\n\n${'#' * int.parse(m[1]!)} ');
  s = s.replaceAll(re(r'<li\b[^>]*>'), '\n- ');
  s = s.replaceAll(re(r'<br\b[^>]*>'), '\n');
  // A <div> is a line (Evernote, Apple Notes); other blocks stand apart.
  s = s.replaceAll(re(r'<div\b[^>]*>'), '');
  s = s.replaceAll(re(r'</(ul|ol|table)\s*>'), '\n\n');
  s = s.replaceAll(
    re(r'</?(p|div|ul|ol|tr|table|blockquote|pre|h[1-6]|section|article)\b[^>]*>'),
    '\n',
  );
  s = s.replaceAll(re(r'</li\s*>'), '');
  s = s.replaceAll(re(r'<[^>]+>'), '');
  s = _entities(s);
  // A list item that holds a to-do: `- [ ] milk`.
  s = s.replaceAllMapped(RegExp(r'^- +(\[[ x]\])', multiLine: true), (m) => '- ${m[1]}');
  final lines = [for (final line in s.split('\n')) line.replaceAll(' ', ' ').trimRight()];
  return lines.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

String _entities(String s) => s.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);'), (m) {
  final code = m[1]!;
  if (code.startsWith('#x') || code.startsWith('#X')) {
    final value = int.tryParse(code.substring(2), radix: 16);
    return value == null ? m[0]! : String.fromCharCode(value);
  }
  if (code.startsWith('#')) {
    final value = int.tryParse(code.substring(1));
    return value == null ? m[0]! : String.fromCharCode(value);
  }
  return switch (code.toLowerCase()) {
    'amp' => '&',
    'lt' => '<',
    'gt' => '>',
    'quot' => '"',
    'apos' => "'",
    'nbsp' => ' ',
    'ndash' => '–',
    'mdash' => '—',
    'hellip' => '…',
    _ => m[0]!,
  };
});
