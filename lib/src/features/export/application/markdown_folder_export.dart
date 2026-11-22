import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../../notes/domain/note.dart';

/// All notes as a folder of Markdown files, zipped (N-7): one `.md` per
/// note with its details in front matter, a folder per notebook, and the
/// note's pictures and files next to them in `_attachments`. Links between
/// notes stay `[[Title]]`, which Obsidian and similar apps read as links,
/// and Notes' own Markdown import reads the folder back.
class MarkdownFolderExport {
  const MarkdownFolderExport._();

  static const attachmentsFolder = '_attachments';

  /// [readFile] decrypts an attachment; one that can't be read (not on this
  /// device yet) is left out and counted in the result.
  static Future<({Uint8List zip, int missing})> build(
    List<Note> notes, {
    Map<String, String> notebookNames = const {},
    Map<String, String> tagNames = const {},
    Future<Uint8List> Function(ZtAttachmentRef file)? readFile,
  }) async {
    final archive = Archive();
    final usedPaths = <String>{};
    final usedAttachments = <String, String>{};
    var missing = 0;

    String unique(String folder, String name, String extension) {
      var candidate = '$folder$name$extension';
      for (var n = 2; usedPaths.contains(candidate.toLowerCase()); n++) {
        candidate = '$folder$name ($n)$extension';
      }
      usedPaths.add(candidate.toLowerCase());
      return candidate;
    }

    void addFile(String path, List<int> bytes) =>
        archive.addFile(ArchiveFile(path, bytes.length, bytes));

    Future<String?> attachment(ZtAttachmentRef file) async {
      final known = usedAttachments[file.id];
      if (known != null) return known;
      if (readFile == null) return null;
      final Uint8List bytes;
      try {
        bytes = await readFile(file);
      } on Object {
        missing++;
        return null;
      }
      final name = safeFileName(file.name ?? file.id, fallback: file.id);
      final dot = name.lastIndexOf('.');
      final path = dot > 0
          ? unique('$attachmentsFolder/', name.substring(0, dot), name.substring(dot))
          : unique('$attachmentsFolder/', name, _extensionFor(file.mimeType));
      addFile(path, bytes);
      usedAttachments[file.id] = path;
      return path;
    }

    for (final note in notes) {
      final notebook = notebookNames[note.notebookId];
      final folder = notebook == null ? '' : '${safeFileName(notebook, fallback: 'Notebook')}/';
      final path = unique(folder, safeFileName(note.title, fallback: 'Untitled'), '.md');
      final up = folder.isEmpty ? '' : '../';

      final links = <String>[];
      for (final image in note.images) {
        final stored = await attachment(image);
        if (stored != null) links.add('![${_label(image)}]($up${_href(stored)})');
      }
      for (final file in note.files) {
        final stored = await attachment(file);
        if (stored != null) links.add('[${_label(file)}]($up${_href(stored)})');
      }

      final text = StringBuffer(frontMatter(note, notebook: notebook, tagNames: tagNames))
        ..writeln()
        ..write(note.body.trimRight());
      if (links.isNotEmpty) {
        text
          ..writeln()
          ..writeln()
          ..write(links.join('\n\n'));
      }
      text.writeln();
      addFile(path, utf8.encode(text.toString()));
    }

    final zip = ZipEncoder().encodeBytes(archive);
    return (zip: zip, missing: missing);
  }

  /// YAML front matter. Values are written as JSON strings, which YAML
  /// reads as they are, so any title is safe.
  static String frontMatter(
    Note note, {
    String? notebook,
    Map<String, String> tagNames = const {},
  }) {
    final tags = [for (final id in note.tagIds) ?tagNames[id]];
    String q(String value) => jsonEncode(value);
    return [
      '---',
      'title: ${q(note.title)}',
      'created: ${note.createdAt.toUtc().toIso8601String()}',
      'updated: ${note.updatedAt.toUtc().toIso8601String()}',
      if (notebook != null) 'notebook: ${q(notebook)}',
      if (tags.isNotEmpty) 'tags: [${tags.map(q).join(', ')}]',
      if (note.pinned) 'pinned: true',
      if (note.archived) 'archived: true',
      if (note.isChecklist) 'checklist: true',
      '---',
      '',
    ].join('\n');
  }

  /// A name any phone or computer accepts as a file name: no slashes or
  /// other reserved characters, not too long. Hebrew and other scripts
  /// stay as they are.
  static String safeFileName(String value, {required String fallback}) {
    var name = value
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    while (name.startsWith('.')) {
      name = name.substring(1).trimLeft();
    }
    if (name.length > 80) name = name.substring(0, 80).trimRight();
    return name.isEmpty ? fallback : name;
  }

  static String _label(ZtAttachmentRef file) =>
      (file.name ?? 'file').replaceAll('[', '(').replaceAll(']', ')');

  /// Spaces and brackets in a relative link.
  static String _href(String path) => path.split('/').map(Uri.encodeComponent).join('/');

  static String _extensionFor(String? mimeType) => switch (mimeType) {
    'image/png' => '.png',
    'image/gif' => '.gif',
    'image/webp' => '.webp',
    'image/jpeg' => '.jpg',
    'application/pdf' => '.pdf',
    'application/json' => '.json',
    _ => '',
  };
}
