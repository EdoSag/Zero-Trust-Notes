import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../notes/application/notes_providers.dart';
import '../notes/domain/note.dart';

/// The text a note is sent as: its title, a blank line, then the text. A
/// checklist is written with ☐ and ☑ boxes (like Keep), not Markdown.
String noteShareText(Note note) {
  final title = note.title.trim();
  final body = note.isChecklist
      ? [
          for (final item in note.checklist!)
            if (item.text.trim().isNotEmpty) '${item.checked ? '☑' : '☐'} ${item.text.trim()}',
        ].join('\n')
      : note.body.trim();
  return [if (title.isNotEmpty) title, if (body.isNotEmpty) body].join('\n\n');
}

/// Hands content to the OS share sheet. Overridden in tests.
typedef ShareSheet = Future<void> Function(ShareParams params);

final shareSheetProvider = Provider<ShareSheet>(
  (ref) =>
      (params) async => SharePlus.instance.share(params),
);

final outgoingShareFilesProvider = Provider<OutgoingShareFiles>((ref) => OutgoingShareFiles());

/// Decrypted images handed to another app. They have to exist as plain
/// files while the other app reads them, which can be after the share
/// sheet closes, so they're deleted when Notes next comes to the front (and
/// on the next start), not straight away.
class OutgoingShareFiles {
  Future<Directory> _dir() async =>
      Directory(p.join((await getTemporaryDirectory()).path, 'outgoing_share'));

  Future<XFile> write(Uint8List bytes, {String? name, String? mimeType}) async {
    final dir = await _dir();
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, '${const Uuid().v4()}${_extension(name, mimeType)}'));
    await file.writeAsBytes(bytes, flush: true);
    return XFile(file.path, mimeType: mimeType, name: name);
  }

  static String _extension(String? name, String? mimeType) {
    final fromName = name == null ? '' : p.extension(name);
    if (fromName.isNotEmpty) return fromName;
    return switch (mimeType) {
      'image/png' => '.png',
      'image/gif' => '.gif',
      'image/webp' => '.webp',
      'image/heic' => '.heic',
      _ => '.jpg',
    };
  }

  Future<void> clear() async {
    if (kIsWeb) return;
    try {
      final dir = await _dir();
      if (await dir.exists()) await dir.delete(recursive: true);
    } on Object {
      // Nothing to clear, or no temp folder in this environment.
    }
  }
}

/// Sends notes and their images to other apps through the share sheet.
class NoteSharing {
  NoteSharing(this.context, this.ref);

  final BuildContext context;
  final WidgetRef ref;

  /// Sends [note] as text, with its images attached when it has any.
  Future<void> shareNote(Note note) async {
    final text = noteShareText(note);
    final images = await _imageFiles(note.images);
    if (text.isEmpty && images.isEmpty) {
      _snack('This note is empty: there is nothing to send.');
      return;
    }
    await _share(
      ShareParams(
        text: text.isEmpty ? null : text,
        subject: note.title.trim().isEmpty ? null : note.title.trim(),
        files: images.isEmpty ? null : images,
      ),
    );
  }

  Future<void> shareImage(ZtAttachmentRef image) async {
    final files = await _imageFiles([image]);
    if (files.isEmpty) return;
    await _share(ShareParams(files: files));
  }

  Future<List<XFile>> _imageFiles(List<ZtAttachmentRef> images) async {
    if (images.isEmpty || kIsWeb) return const [];
    final repository = ref.read(notesRepositoryProvider);
    if (repository == null) return const [];
    final outgoing = ref.read(outgoingShareFilesProvider);
    await outgoing.clear();
    final files = <XFile>[];
    var missing = 0;
    for (final image in images) {
      try {
        final bytes = await repository.readImage(image);
        files.add(await outgoing.write(bytes, name: image.name, mimeType: image.mimeType));
      } on Object {
        missing++;
      }
    }
    if (missing > 0) {
      _snack(
        missing == 1
            ? 'One image isn\'t on this device yet, so it wasn\'t sent.'
            : '$missing images aren\'t on this device yet, so they weren\'t sent.',
      );
    }
    return files;
  }

  Future<void> _share(ShareParams params) async {
    try {
      await ref
          .read(vaultControllerProvider.notifier)
          .whileShowingSystemUi(() => ref.read(shareSheetProvider)(params));
    } on Object {
      _snack('Couldn\'t open the share sheet.');
    }
  }

  void _snack(String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
  }
}
