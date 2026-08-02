import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

/// Web has no OS temp directory to write into; the bytes are handed to
/// `share_plus` in memory instead, so there's never a temp file here to
/// track or clean up.
Future<(XFile, String?)> writeExportFile({
  required List<int> bytes,
  required String fileName,
  required String mimeType,
}) async {
  final xFile = XFile.fromData(Uint8List.fromList(bytes), name: fileName, mimeType: mimeType);
  return (xFile, null);
}

Future<void> deleteExportFile(String? path) async {
  // No-op: web never returns a path from writeExportFile.
}
