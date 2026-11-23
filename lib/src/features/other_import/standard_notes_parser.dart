import 'dart:convert';

import 'imported_note.dart';

/// A Standard Notes backup (N-1): notes, tags, pins, archive and trash. An
/// encrypted backup can't be read here; those notes are only counted.
class StandardNotesParser {
  const StandardNotesParser();

  /// Null when [bytes] isn't a Standard Notes backup.
  ({List<ImportedNote> notes, int encrypted})? parse(List<int> bytes) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
    } on FormatException {
      return null;
    }
    if (decoded is! Map || decoded['items'] is! List) return null;
    final items = [
      for (final item in decoded['items'] as List)
        if (item is Map) item.cast<String, Object?>(),
    ];
    if (!items.any((item) => item['content_type'] is String)) return null;

    // Tags point at their notes.
    final tagsOf = <String, List<String>>{};
    for (final item in items) {
      final content = item['content'];
      if (item['content_type'] != 'Tag' || content is! Map || item['deleted'] == true) continue;
      final title = (content['title'] as String?)?.trim() ?? '';
      if (title.isEmpty) continue;
      for (final ref in (content['references'] as List?) ?? const []) {
        if (ref is Map && ref['uuid'] is String) {
          (tagsOf[ref['uuid'] as String] ??= []).add(title);
        }
      }
    }

    final notes = <ImportedNote>[];
    var encrypted = 0;
    for (final item in items) {
      if (item['content_type'] != 'Note' || item['deleted'] == true) continue;
      final content = item['content'];
      if (content is! Map) {
        if (content is String) encrypted++;
        continue;
      }
      final app = content['appData'];
      final sn = app is Map ? app['org.standardnotes.sn'] : null;
      bool flag(String key) => sn is Map && sn[key] == true;
      var text = (content['text'] as String?) ?? '';
      if (content['noteType'] == 'super') text = superNoteText(text);
      notes.add(
        ImportedNote(
          title: (content['title'] as String?) ?? '',
          body: text.trimRight(),
          tags: tagsOf[item['uuid']] ?? const [],
          createdAt: DateTime.tryParse((item['created_at'] as String?) ?? '')?.toUtc(),
          pinned: flag('pinned'),
          archived: flag('archived'),
          trashed: content['trashed'] == true,
        ),
      );
    }
    return (notes: notes, encrypted: encrypted);
  }

  /// A "Super" note's text: the editor keeps it as a JSON tree.
  static String superNoteText(String json) {
    final Object? tree;
    try {
      tree = jsonDecode(json);
    } on FormatException {
      return json;
    }
    final out = StringBuffer();
    void walk(Object? node) {
      if (node is! Map) return;
      final type = node['type'];
      if (type == 'text' || type == 'code-highlight') {
        out.write(node['text'] ?? '');
        return;
      }
      if (type == 'linebreak') {
        out.writeln();
        return;
      }
      if (type == 'listitem') {
        out.write(switch (node['checked']) {
          true => '- [x] ',
          false => '- [ ] ',
          _ => '- ',
        });
      }
      if (type == 'heading' && node['tag'] is String) {
        final level = int.tryParse((node['tag'] as String).substring(1)) ?? 1;
        out.write('${'#' * level} ');
      }
      for (final child in (node['children'] as List?) ?? const []) {
        walk(child);
      }
      if (const {'paragraph', 'heading', 'listitem', 'quote', 'code'}.contains(type)) {
        out.writeln();
      }
    }

    walk(tree is Map ? tree['root'] : null);
    return out.toString().replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }
}
