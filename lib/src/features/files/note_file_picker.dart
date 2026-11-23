import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:zero_trust_core/zero_trust_core.dart';

/// A file chosen to attach. [read] loads it only when its turn comes, and
/// [size] (when the system knows it) lets a too-large file be refused
/// without reading it.
typedef PickedNoteFile = ({String name, int? size, Future<Uint8List> Function() read});

/// Opens the system file chooser. Overridable in tests.
typedef NoteFilePicker = Future<List<PickedNoteFile>> Function();

final noteFilePickerProvider = Provider<NoteFilePicker>(
  (ref) => () async {
    final picked = await FilePicker.pickFiles();
    return [
      for (final file in picked)
        (name: file.name, size: file.lengthSync() ?? await file.length(), read: file.readAsBytes),
    ];
  },
);

/// The most a single attached file may be: the shared attachment limit.
const maxNoteFileBytes = ZtAttachments.defaultMaxBytes;

/// A file's type from its name, for the types people attach most. Null
/// when unknown; the file is kept and opened by name.
String? fileMimeType(String name) => switch (p.extension(name).toLowerCase()) {
  '.pdf' => 'application/pdf',
  '.txt' => 'text/plain',
  '.md' || '.markdown' => 'text/markdown',
  '.csv' => 'text/csv',
  '.html' || '.htm' => 'text/html',
  '.json' => 'application/json',
  '.zip' => 'application/zip',
  '.doc' => 'application/msword',
  '.docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  '.xls' => 'application/vnd.ms-excel',
  '.xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  '.ppt' => 'application/vnd.ms-powerpoint',
  '.pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  '.odt' => 'application/vnd.oasis.opendocument.text',
  '.ods' => 'application/vnd.oasis.opendocument.spreadsheet',
  '.epub' => 'application/epub+zip',
  '.mp3' => 'audio/mpeg',
  '.m4a' => 'audio/mp4',
  '.ogg' => 'audio/ogg',
  '.wav' => 'audio/wav',
  '.mp4' => 'video/mp4',
  '.jpg' || '.jpeg' => 'image/jpeg',
  '.png' => 'image/png',
  '.gif' => 'image/gif',
  '.webp' => 'image/webp',
  '.heic' => 'image/heic',
  _ => null,
};
