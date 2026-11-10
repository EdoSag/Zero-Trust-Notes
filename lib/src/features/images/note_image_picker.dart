import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// An image chosen or taken on this device, still in memory only.
class PickedImage {
  const PickedImage({required this.bytes, this.mimeType, this.name});

  final Uint8List bytes;
  final String? mimeType;
  final String? name;
}

enum NoteImageSource { camera, gallery }

/// Picks images for a note. Overridden in tests.
abstract interface class NoteImagePicker {
  /// Empty when the person cancels.
  Future<List<PickedImage>> pick(NoteImageSource source);
}

final noteImagePickerProvider = Provider<NoteImagePicker>((ref) => const SystemNoteImagePicker());

/// The system camera and photo picker. Images are scaled down to at most
/// 2560 px on the long side and re-compressed, so a note full of photos
/// stays quick to sync and well under the 20 MB attachment limit.
class SystemNoteImagePicker implements NoteImagePicker {
  const SystemNoteImagePicker();

  static const _maxSide = 2560.0;
  static const _quality = 85;

  @override
  Future<List<PickedImage>> pick(NoteImageSource source) async {
    final picker = ImagePicker();
    final files = switch (source) {
      NoteImageSource.camera => [
        ?await picker.pickImage(
          source: ImageSource.camera,
          maxWidth: _maxSide,
          maxHeight: _maxSide,
          imageQuality: _quality,
        ),
      ],
      NoteImageSource.gallery => await picker.pickMultiImage(
        maxWidth: _maxSide,
        maxHeight: _maxSide,
        imageQuality: _quality,
      ),
    };
    final picked = <PickedImage>[];
    for (final file in files) {
      try {
        picked.add(
          PickedImage(
            bytes: await file.readAsBytes(),
            mimeType: file.mimeType ?? mimeTypeForName(file.name),
            name: file.name,
          ),
        );
      } finally {
        await _deleteCopy(file);
      }
    }
    return picked;
  }

  /// The picker leaves a plain copy of every image (the photo just taken,
  /// or the scaled-down one) in the app's cache. Only the encrypted version
  /// should stay on the device.
  /// Only ever inside the app's own temporary folders: never a person's
  /// original photo.
  static Future<void> _deleteCopy(XFile file) async {
    if (kIsWeb) return;
    try {
      final roots = [(await getTemporaryDirectory()).path, Directory.systemTemp.path];
      if (!roots.any((root) => p.isWithin(root, file.path))) return;
      await File(file.path).delete();
    } on Object {
      // Already gone, or not ours to delete.
    }
  }
}

/// A best guess from the file extension, for pickers that don't say.
String? mimeTypeForName(String? name) {
  final dot = name?.lastIndexOf('.') ?? -1;
  if (name == null || dot < 0) return null;
  return switch (name.substring(dot + 1).toLowerCase()) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'heif' => 'image/heif',
    'bmp' => 'image/bmp',
    _ => null,
  };
}
