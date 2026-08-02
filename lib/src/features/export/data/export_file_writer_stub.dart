import 'package:cross_file/cross_file.dart';

Future<(XFile, String?)> writeExportFile({
  required List<int> bytes,
  required String fileName,
  required String mimeType,
}) {
  throw UnsupportedError('No export file writer implementation for this platform.');
}

Future<void> deleteExportFile(String? path) async {}
