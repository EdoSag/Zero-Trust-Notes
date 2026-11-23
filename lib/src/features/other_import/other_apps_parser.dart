import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'evernote_parser.dart';
import 'imported_note.dart';
import 'markdown_folder_parser.dart';
import 'standard_notes_parser.dart';

/// What was found in the chosen files.
class ImportBatch {
  const ImportBatch({required this.notes, this.encrypted = 0});

  final List<ImportedNote> notes;

  /// Notes from an encrypted Standard Notes backup, which can't be read.
  final int encrypted;
}

/// Reads whatever was chosen (N-1): Evernote `.enex`, a Standard Notes
/// backup, and Markdown, text or HTML notes (Apple Notes, Obsidian, Notes'
/// own export), loose or in `.zip` files. Pure Dart, so it can run off the
/// screen thread.
ImportBatch parseOtherAppsFiles(Map<String, List<int>> chosen) {
  final files = <String, List<int>>{};
  for (final MapEntry(key: name, value: bytes) in chosen.entries) {
    if (p.extension(name).toLowerCase() != '.zip') {
      files[name] = bytes;
      continue;
    }
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on Object {
      continue;
    }
    for (final file in archive.files) {
      final path = file.name.replaceAll('\\', '/');
      final hidden = path.startsWith('__MACOSX/') || p.basename(path).startsWith('.');
      if (file.isFile && !hidden) files[path] = file.content;
    }
  }

  final notes = <ImportedNote>[];
  var encrypted = 0;
  final rest = <String, List<int>>{};
  final enex = [
    for (final name in files.keys)
      if (p.extension(name).toLowerCase() == '.enex') name,
  ];
  for (final MapEntry(key: name, value: bytes) in files.entries) {
    final extension = p.extension(name).toLowerCase();
    if (extension == '.enex') {
      // Several exports are usually one per notebook, named after it.
      final notebook = enex.length > 1 ? p.basenameWithoutExtension(name) : null;
      notes.addAll(const EvernoteParser().parse(bytes, notebook: notebook) ?? const []);
      continue;
    }
    if ((extension == '.json' || extension == '.txt') && _looksLikeJson(bytes)) {
      final backup = const StandardNotesParser().parse(bytes);
      if (backup != null) {
        notes.addAll(backup.notes);
        encrypted += backup.encrypted;
        continue;
      }
      // Other JSON stays: a note may link to it as a file.
    }
    rest[name] = bytes;
  }
  notes.addAll(const MarkdownFolderParser().parse(rest));
  return ImportBatch(notes: notes, encrypted: encrypted);
}

bool _looksLikeJson(List<int> bytes) {
  for (final byte in bytes.take(64)) {
    if (byte == 0x7B) return true; // {
    if (byte != 0x20 &&
        byte != 0x0A &&
        byte != 0x0D &&
        byte != 0x09 &&
        byte != 0xEF &&
        byte != 0xBB &&
        byte != 0xBF) {
      return false;
    }
  }
  return false;
}
