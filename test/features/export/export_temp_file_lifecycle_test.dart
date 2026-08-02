import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_notes/src/features/export/application/export_temp_file_registry.dart';
import 'package:zerotrust_notes/src/features/export/data/export_file_writer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // `flutter test` has no real path_provider platform implementation to
  // answer this method channel, so point it at a real OS temp directory
  // ourselves — the point of these tests is exercising real file I/O, not
  // path_provider's own plumbing.
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => Directory.systemTemp.path,
    );
  });
  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('writeExportFile writes bytes to a real temp file on native platforms', () async {
    final (xFile, path) = await writeExportFile(
      bytes: utf8.encode('hello export'),
      fileName: 'lifecycle_test_note.md',
      mimeType: 'text/markdown',
    );

    expect(path, isNotNull);
    expect(File(path!).existsSync(), isTrue);
    expect(await File(path).readAsString(), 'hello export');
    expect(xFile.name, 'lifecycle_test_note.md');

    await deleteExportFile(path);
    expect(File(path).existsSync(), isFalse);
  });

  test('deleteExportFile is safe to call on an already-deleted path', () async {
    final (_, path) = await writeExportFile(
      bytes: utf8.encode('x'),
      fileName: 'lifecycle_test_double_delete.md',
      mimeType: 'text/markdown',
    );

    await deleteExportFile(path);
    // Second delete of the same (now-missing) path must not throw.
    await deleteExportFile(path);
  });

  test('ExportTempFileRegistry.deleteAll force-deletes every registered file', () async {
    final registry = ExportTempFileRegistry();

    final (_, pathA) = await writeExportFile(
      bytes: utf8.encode('a'),
      fileName: 'lifecycle_test_registry_a.md',
      mimeType: 'text/markdown',
    );
    final (_, pathB) = await writeExportFile(
      bytes: utf8.encode('b'),
      fileName: 'lifecycle_test_registry_b.md',
      mimeType: 'text/markdown',
    );

    registry.register(pathA!);
    registry.register(pathB!);

    expect(File(pathA).existsSync(), isTrue);
    expect(File(pathB).existsSync(), isTrue);

    await registry.deleteAll();

    expect(File(pathA).existsSync(), isFalse);
    expect(File(pathB).existsSync(), isFalse);
  });

  test('unregistering a file before deleteAll leaves it untouched', () async {
    final registry = ExportTempFileRegistry();

    final (_, path) = await writeExportFile(
      bytes: utf8.encode('kept'),
      fileName: 'lifecycle_test_kept.md',
      mimeType: 'text/markdown',
    );

    registry.register(path!);
    registry.unregister(path);
    await registry.deleteAll();

    expect(File(path).existsSync(), isTrue);

    // Clean up what this test itself created.
    await deleteExportFile(path);
  });
}
