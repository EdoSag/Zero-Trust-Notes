import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/export_file_writer.dart';

/// Tracks temp export files currently "in flight" (written but not yet
/// cleaned up) so the app's lifecycle observer can force-delete them if the
/// app backgrounds mid-export — otherwise decrypted note content could be
/// left sitting in the OS temp directory indefinitely. No-ops for web,
/// which never writes a temp file in the first place.
class ExportTempFileRegistry {
  final _pendingPaths = <String>{};

  void register(String path) => _pendingPaths.add(path);

  void unregister(String path) => _pendingPaths.remove(path);

  Future<void> deleteAll() async {
    final paths = _pendingPaths.toList();
    _pendingPaths.clear();
    for (final path in paths) {
      await deleteExportFile(path);
    }
  }
}

final exportTempFileRegistryProvider = Provider<ExportTempFileRegistry>((ref) {
  return ExportTempFileRegistry();
});
