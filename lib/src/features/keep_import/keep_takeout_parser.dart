import 'dart:convert';

import 'package:archive/archive.dart';

import '../notes/domain/checklist_item.dart';
import '../notes/domain/note_color.dart';

/// One note read from a Google Keep Takeout export.
class KeepNote {
  const KeepNote({
    required this.title,
    required this.body,
    required this.color,
    required this.pinned,
    required this.archived,
    required this.trashed,
    required this.labels,
    this.checklist,
    this.createdAt,
    this.editedAt,
    this.attachmentCount = 0,
  });

  final String title;
  final String body;
  final NoteColor color;
  final bool pinned;
  final bool archived;
  final bool trashed;
  final List<String> labels;
  final List<ChecklistItem>? checklist;
  final DateTime? createdAt;
  final DateTime? editedAt;

  /// Images and recordings aren't imported yet; counted so the user is told.
  final int attachmentCount;

  bool get isEmpty =>
      title.trim().isEmpty && body.trim().isEmpty && (checklist?.isEmpty ?? true);
}

/// Reads Google Keep notes out of a Takeout export: either the whole
/// `takeout-*.zip`, or the `.json` files from its `Takeout/Keep` folder.
/// Everything happens on the device; nothing is uploaded.
class KeepTakeoutParser {
  const KeepTakeoutParser();

  /// [files] maps each picked file's name to its bytes.
  List<KeepNote> parseFiles(Map<String, List<int>> files) {
    final notes = <KeepNote>[];
    for (final MapEntry(key: name, value: bytes) in files.entries) {
      final lower = name.toLowerCase();
      if (lower.endsWith('.zip')) {
        notes.addAll(parseZip(bytes));
      } else if (lower.endsWith('.json')) {
        final note = parseJson(bytes);
        if (note != null) notes.add(note);
      }
    }
    return notes;
  }

  List<KeepNote> parseZip(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final notes = <KeepNote>[];
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final path = file.name.replaceAll('\\', '/');
      // Keep's notes are the .json files in a "Keep" folder; Takeout zips
      // can also hold other Google products.
      if (!path.toLowerCase().endsWith('.json')) continue;
      final segments = path.split('/');
      if (segments.length < 2 || segments[segments.length - 2] != 'Keep') continue;
      final note = parseJson(file.content);
      if (note != null) notes.add(note);
    }
    return notes;
  }

  /// `null` when [bytes] isn't a Keep note (for example Labels.txt's JSON
  /// cousins or an unrelated file).
  KeepNote? parseJson(List<int> bytes) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final json = decoded.cast<String, Object?>();
    final hasText = json.containsKey('textContent');
    final hasList = json['listContent'] is List;
    if (!hasText && !hasList && !json.containsKey('title')) return null;

    List<ChecklistItem>? checklist;
    if (hasList) {
      checklist = ChecklistItem.ordered([
        for (final entry in json['listContent']! as List)
          if (entry is Map)
            ChecklistItem.create(
              (entry['text'] as String?) ?? '',
              checked: entry['isChecked'] == true,
            ),
      ]);
    }

    final annotations = [
      for (final annotation in (json['annotations'] as List?) ?? const [])
        if (annotation is Map && annotation['url'] is String)
          '[${(annotation['title'] as String?)?.trim().isNotEmpty == true ? annotation['title'] : annotation['url']}](${annotation['url']})',
    ];
    var body = checklist != null
        ? ChecklistItem.toMarkdown(checklist)
        : (json['textContent'] as String?) ?? '';
    if (annotations.isNotEmpty) {
      body = [if (body.isNotEmpty) body, ...annotations].join('\n\n');
    }

    return KeepNote(
      title: (json['title'] as String?) ?? '',
      body: body,
      color: NoteColor.fromKeep(json['color'] as String?),
      pinned: json['isPinned'] == true,
      archived: json['isArchived'] == true,
      trashed: json['isTrashed'] == true,
      labels: [
        for (final label in (json['labels'] as List?) ?? const [])
          if (label is Map && (label['name'] as String?)?.trim().isNotEmpty == true)
            (label['name'] as String).trim(),
      ],
      checklist: checklist,
      createdAt: _usec(json['createdTimestampUsec']),
      editedAt: _usec(json['userEditedTimestampUsec']),
      attachmentCount: (json['attachments'] as List?)?.length ?? 0,
    );
  }

  static DateTime? _usec(Object? value) {
    final micros = switch (value) {
      final int v => v,
      final String s => int.tryParse(s),
      _ => null,
    };
    if (micros == null || micros <= 0) return null;
    return DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);
  }
}
