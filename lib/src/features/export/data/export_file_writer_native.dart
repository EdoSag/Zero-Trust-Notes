import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<(XFile, String?)> writeExportFile({
  required List<int> bytes,
  required String fileName,
  required String mimeType,
}) async {
  final tempDir = await getTemporaryDirectory();
  final path = p.join(tempDir.path, fileName);
  await File(path).writeAsBytes(bytes, flush: true);
  return (XFile(path, mimeType: mimeType), path);
}

Future<void> deleteExportFile(String? path) async {
  if (path == null) return;
  final file = File(path);
  if (file.existsSync()) {
    await file.delete();
  }
}
