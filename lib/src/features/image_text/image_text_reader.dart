import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Which language(s) to read an image in.
enum ImageTextLanguage {
  /// English and Hebrew together, the app's language first.
  both,
  english,
  hebrew;

  /// Tesseract's language string. With both, the first is the main one.
  String tesseract({required bool hebrewFirst}) => switch (this) {
    ImageTextLanguage.english => 'eng',
    ImageTextLanguage.hebrew => 'heb',
    ImageTextLanguage.both => hebrewFirst ? 'heb+eng' : 'eng+heb',
  };
}

/// Reads the text in an image on this phone. Overridden in tests.
abstract interface class ImageTextReader {
  bool get supported;

  /// The text in [bytes] (an encoded image), tidied: trailing spaces and
  /// runs of blank lines dropped. Empty when there is none.
  Future<String> read(Uint8List bytes, {required String languages});
}

final imageTextReaderProvider = Provider<ImageTextReader>(
  (ref) => const TesseractImageTextReader(),
);

/// Tesseract, an open-source recogniser bundled with the app (English and
/// Hebrew models in assets/tessdata). Nothing is uploaded: the image is
/// written to the app's own temporary folder for Tesseract to open, and
/// deleted as soon as it has been read.
class TesseractImageTextReader implements ImageTextReader {
  const TesseractImageTextReader();

  @override
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<String> read(Uint8List bytes, {required String languages}) async {
    final dir = Directory(p.join((await getTemporaryDirectory()).path, 'image_text'));
    await dir.create(recursive: true);
    final name = List.generate(16, (_) => Random.secure().nextInt(16).toRadixString(16)).join();
    final file = File(p.join(dir.path, '$name.img'));
    try {
      await file.writeAsBytes(bytes, flush: true);
      // 3: find the page layout by itself (paragraphs, columns), which suits
      // documents, signs and whiteboards.
      final text = await FlutterTesseractOcr.extractText(
        file.path,
        language: languages,
        args: const {'psm': '3', 'preserve_interword_spaces': '1'},
      );
      return tidyImageText(text);
    } finally {
      try {
        await file.delete();
      } on Object {
        // Already gone.
      }
    }
  }
}

/// Trims each line, and keeps at most one blank line between paragraphs.
String tidyImageText(String raw) {
  final lines = raw.replaceAll('\r', '').split('\n').map((l) => l.trimRight()).toList();
  final out = <String>[];
  for (final line in lines) {
    if (line.trim().isEmpty && (out.isEmpty || out.last.isEmpty)) continue;
    out.add(line.trim().isEmpty ? '' : line);
  }
  while (out.isNotEmpty && out.last.isEmpty) {
    out.removeLast();
  }
  return out.join('\n');
}
