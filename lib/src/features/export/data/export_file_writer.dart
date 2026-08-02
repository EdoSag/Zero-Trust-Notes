import 'package:cross_file/cross_file.dart';

export 'export_file_writer_stub.dart'
    if (dart.library.io) 'export_file_writer_native.dart'
    if (dart.library.js_interop) 'export_file_writer_web.dart';

/// Writes export content somewhere shareable and returns the resulting
/// file plus, on native platforms, the temp file path it was written to
/// (so it can be tracked and force-deleted). Web returns a null path since
/// its implementation holds the bytes in memory — there's no temp file to
/// clean up there.
typedef WriteExportFile = Future<(XFile, String?)> Function({
  required List<int> bytes,
  required String fileName,
  required String mimeType,
});

/// Deletes the file at [path], if any. No-ops when `path` is null (the web
/// implementation never returns one, since it never wrote a temp file).
typedef DeleteExportFile = Future<void> Function(String? path);
