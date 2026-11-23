import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../files/note_file_picker.dart';
import 'imported_note.dart';

/// A folder of Markdown, text or HTML files, one per note (N-1): Notes' own
/// Markdown folder export, Obsidian, Joplin and Standard Notes plain-text
/// exports, and Apple Notes as exported by Apple's data copy or by
/// exporter apps. Folders become notebooks; pictures and files that a note
/// links to (or that sit in a note's own folder) are attached to it.
class MarkdownFolderParser {
  const MarkdownFolderParser();

  static const noteExtensions = {'.md', '.markdown', '.txt', '.html', '.htm'};

  static bool isNoteFile(String path) => noteExtensions.contains(p.extension(path).toLowerCase());

  /// [files]: path inside the folder (with `/`) -> contents.
  List<ImportedNote> parse(Map<String, List<int>> files) {
    final paths = [for (final path in files.keys) path.replaceAll('\\', '/')];
    final byPath = {for (final (i, path) in files.keys.indexed) paths[i]: files[path]!};
    final notePaths = [
      for (final path in paths)
        if (isNoteFile(path)) path,
    ]..sort();
    if (notePaths.isEmpty) return const [];

    // One folder around everything (the zip's own folder) isn't a notebook.
    var root = 0;
    while (true) {
      final firsts = {
        for (final path in notePaths)
          if (path.split('/').length > root + 1) path.split('/')[root] else null,
      };
      if (firsts.length != 1 || firsts.single == null) break;
      root++;
    }

    final byName = <String, List<String>>{};
    for (final path in paths) {
      if (!isNoteFile(path)) (byName[p.basename(path).toLowerCase()] ??= []).add(path);
    }

    return [
      for (final path in notePaths)
        _note(path, byPath[path]!, root: root, all: byPath, byName: byName),
    ];
  }

  ImportedNote _note(
    String path,
    List<int> bytes, {
    required int root,
    required Map<String, List<int>> all,
    required Map<String, List<String>> byName,
  }) {
    final segments = path.split('/');
    final extension = p.extension(path).toLowerCase();
    final base = p.basenameWithoutExtension(path);
    var folders = segments.sublist(root, segments.length - 1);
    // Apple Notes' data copy keeps each note in a folder of its own name.
    final ownFolder = folders.isNotEmpty && folders.last == base;
    if (ownFolder) folders = folders.sublist(0, folders.length - 1);

    var text = utf8.decode(bytes, allowMalformed: true).replaceAll('\r\n', '\n');
    if (text.startsWith('﻿')) text = text.substring(1);
    if (extension == '.html' || extension == '.htm') text = htmlToText(text);
    final (:fields, :body) = splitFrontMatter(text);
    text = body;

    String? field(String key) => switch (fields[key]) {
      final String s when s.trim().isNotEmpty => s.trim(),
      _ => null,
    };

    var title = field('title');
    if (title == null) {
      final lines = text.split('\n');
      final first = lines.isEmpty ? '' : lines.first.trim();
      final heading = RegExp(r'^#\s+(.+)$').firstMatch(first);
      if (heading != null && extension != '.txt') {
        title = heading.group(1)!.trim();
        text = lines.skip(1).join('\n');
      } else {
        title = base;
        // Plain-text exports often repeat the title as the first line.
        if (first == base.trim()) text = lines.skip(1).join('\n');
      }
    }

    // Linked pictures and files.
    final files = <ImportedFile>[];
    final taken = <String>{};
    void attach(String target) {
      if (!taken.add(target)) return;
      final name = p.basename(target);
      files.add(
        ImportedFile(
          name: name,
          mimeType: fileMimeType(name),
          bytes: Uint8List.fromList(all[target]!),
        ),
      );
    }

    String? resolve(String link) {
      var target = link.trim();
      if (target.startsWith('<') && target.endsWith('>')) {
        target = target.substring(1, target.length - 1);
      }
      if (RegExp(r'^[a-z][a-z0-9+.-]*:', caseSensitive: false).hasMatch(target)) return null;
      target = target.split('#').first.split('?').first;
      try {
        target = Uri.decodeFull(target);
      } on ArgumentError {
        // Not percent-encoded.
      }
      if (target.isEmpty) return null;
      final joined = p.posix.normalize(p.posix.join(p.posix.dirname(path), target));
      if (all.containsKey(joined) && !isNoteFile(joined)) return joined;
      final named = byName[p.basename(target).toLowerCase()];
      return named != null && named.length == 1 ? named.single : null;
    }

    final link = RegExp(r'!?\[[^\]\n]*\]\(([^)\n]+)\)|!\[\[([^\]|\n]+)(?:\|[^\]\n]*)?\]\]');
    text = text.replaceAllMapped(link, (m) {
      final target = resolve(m.group(1) ?? m.group(2)!);
      if (target == null) return m.group(0)!;
      attach(target);
      return '';
    });
    if (ownFolder) {
      final folder = p.posix.dirname(path);
      for (final other in (all.keys.toList()..sort())) {
        if (p.posix.dirname(other) == folder && !isNoteFile(other)) attach(other);
      }
    }
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

    final tags = switch (fields['tags']) {
      final List<String> list => list,
      final String s => [
        for (final tag in s.split(','))
          if (tag.trim().isNotEmpty) tag.trim(),
      ],
      _ => const <String>[],
    };
    return ImportedNote(
      title: title,
      body: text,
      tags: [for (final tag in tags) tag.startsWith('#') ? tag.substring(1) : tag],
      notebook: field('notebook') ?? (folders.isEmpty ? null : folders.join(' / ')),
      createdAt: DateTime.tryParse(field('created') ?? field('date') ?? '')?.toUtc(),
      pinned: fields['pinned'] == 'true',
      archived: fields['archived'] == 'true',
      checklist: checklistOf(text),
      files: files,
    );
  }

  /// YAML front matter (`---` lines at the top) as simple fields: text,
  /// `true`/`false` as text, and lists (`[a, b]` or `- a` lines) as lists.
  static ({Map<String, Object> fields, String body}) splitFrontMatter(String text) {
    if (!text.startsWith('---\n')) return (fields: const {}, body: text);
    final end = RegExp(r'^---\s*$', multiLine: true).allMatches(text, 4).firstOrNull;
    if (end == null) return (fields: const {}, body: text);
    final fields = <String, Object>{};
    String? listKey;
    for (final line in text.substring(4, end.start).split('\n')) {
      final item = RegExp(r'^\s+-\s+(.*)$').firstMatch(line);
      if (item != null && listKey != null) {
        (fields[listKey] as List<String>).add(_scalar(item.group(1)!));
        continue;
      }
      final pair = RegExp(r'^([A-Za-z_][\w-]*)\s*:\s*(.*)$').firstMatch(line);
      if (pair == null) continue;
      final key = pair.group(1)!.toLowerCase();
      final value = pair.group(2)!.trim();
      listKey = null;
      if (value.isEmpty) {
        fields[key] = <String>[];
        listKey = key;
      } else if (value.startsWith('[') && value.endsWith(']')) {
        fields[key] = [
          for (final part in _splitList(value.substring(1, value.length - 1)))
            if (part.isNotEmpty) part,
        ];
      } else {
        fields[key] = _scalar(value);
      }
    }
    var body = text.substring(end.end);
    if (body.startsWith('\n')) body = body.substring(1);
    return (fields: fields, body: body);
  }

  static List<String> _splitList(String inner) {
    final parts = <String>[];
    final quoted = RegExp(r'''\s*("(?:[^"\\]|\\.)*"|'[^']*'|[^,]+)\s*(?:,|$)''');
    for (final m in quoted.allMatches(inner)) {
      parts.add(_scalar(m.group(1)!.trim()));
    }
    return parts;
  }

  static String _scalar(String value) {
    final v = value.trim();
    if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
      try {
        return jsonDecode(v) as String;
      } on FormatException {
        return v.substring(1, v.length - 1);
      }
    }
    if (v.length >= 2 && v.startsWith("'") && v.endsWith("'")) {
      return v.substring(1, v.length - 1).replaceAll("''", "'");
    }
    return v;
  }
}
