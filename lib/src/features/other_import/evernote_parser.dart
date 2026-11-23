import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'imported_note.dart';

/// Evernote's export file (`.enex`): every note with its text, tags, dates
/// and attached pictures and files (N-1).
class EvernoteParser {
  const EvernoteParser();

  /// Null when [bytes] isn't an Evernote export.
  List<ImportedNote>? parse(List<int> bytes, {String? notebook}) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(utf8.decode(bytes, allowMalformed: true));
    } on Object {
      return null;
    }
    final root = document.rootElement;
    if (root.name.local != 'en-export') return null;
    return [for (final note in root.findElements('note')) _note(note, notebook)];
  }

  ImportedNote _note(XmlElement note, String? notebook) {
    String? text(String name) => note.getElement(name)?.innerText.trim();
    final content = note.getElement('content')?.innerText ?? '';
    final body = htmlToText(_enNote(content));
    final files = <ImportedFile>[];
    var index = 0;
    for (final resource in note.findElements('resource')) {
      index++;
      final data = resource.getElement('data');
      if (data == null) continue;
      final Uint8List bytes;
      try {
        bytes = base64Decode(data.innerText.replaceAll(RegExp(r'\s'), ''));
      } on FormatException {
        continue;
      }
      final mime = resource.getElement('mime')?.innerText.trim();
      final name = resource.getElement('resource-attributes')?.getElement('file-name')?.innerText;
      files.add(
        ImportedFile(
          name: (name == null || name.trim().isEmpty) ? 'Attachment $index' : name.trim(),
          mimeType: (mime == null || mime.isEmpty) ? null : mime,
          bytes: bytes,
        ),
      );
    }
    final checklist = checklistOf(body);
    return ImportedNote(
      title: text('title') ?? '',
      body: body,
      tags: [
        for (final tag in note.findElements('tag'))
          if (tag.innerText.trim().isNotEmpty) tag.innerText.trim(),
      ],
      notebook: notebook,
      createdAt: evernoteDate(text('created')),
      checklist: checklist,
      files: files,
    );
  }

  /// The note's HTML: what's inside `<en-note>`.
  static String _enNote(String content) {
    final match = RegExp(r'<en-note\b[^>]*>(.*)</en-note>', dotAll: true).firstMatch(content);
    return match?.group(1) ?? content;
  }

  /// `20231122T101500Z`.
  static DateTime? evernoteDate(String? value) {
    final m = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z?$').firstMatch(value ?? '');
    if (m == null) return null;
    int g(int i) => int.parse(m.group(i)!);
    return DateTime.utc(g(1), g(2), g(3), g(4), g(5), g(6));
  }
}
