import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';

import '../../shared/text_direction.dart';
import 'image_text_reader.dart';

/// Reads the text in [image] on this phone and shows it, editable, with
/// Copy and Add to note. Returns the text to add, or null.
Future<String?> showImageTextSheet(BuildContext context, Uint8List image) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ImageTextSheet(image: image),
    );

class ImageTextSheet extends ConsumerStatefulWidget {
  const ImageTextSheet({super.key, required this.image});

  final Uint8List image;

  @override
  ConsumerState<ImageTextSheet> createState() => _ImageTextSheetState();
}

class _ImageTextSheetState extends ConsumerState<ImageTextSheet> {
  final _text = TextEditingController();
  ImageTextLanguage _language = ImageTextLanguage.both;
  bool _reading = true;
  bool _failed = false;
  int _run = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _read());
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    final run = ++_run;
    setState(() {
      _reading = true;
      _failed = false;
    });
    final hebrewFirst = Localizations.localeOf(context).languageCode == 'he';
    String text;
    var failed = false;
    try {
      text = await ref
          .read(imageTextReaderProvider)
          .read(widget.image, languages: _language.tesseract(hebrewFirst: hebrewFirst));
    } on Object {
      text = '';
      failed = true;
    }
    if (!mounted || run != _run) return;
    setState(() {
      _reading = false;
      _failed = failed;
      _text.text = text;
    });
  }

  void _setLanguage(ImageTextLanguage language) {
    if (language == _language) return;
    setState(() => _language = language);
    _read();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _text.text));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(context.l10n.textCopied), duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final hasText = !_reading && _text.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.imageTextTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(l10n.imageTextPrivacy, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          SegmentedButton<ImageTextLanguage>(
            key: const Key('image_text_language'),
            segments: [
              ButtonSegment(value: ImageTextLanguage.both, label: Text(l10n.ocrBoth)),
              ButtonSegment(value: ImageTextLanguage.english, label: Text(l10n.ocrEnglish)),
              ButtonSegment(value: ImageTextLanguage.hebrew, label: Text(l10n.ocrHebrew)),
            ],
            selected: {_language},
            onSelectionChanged: _reading ? null : (v) => _setLanguage(v.first),
          ),
          const SizedBox(height: 12),
          if (_reading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(l10n.readingImageText, key: const Key('image_text_reading')),
                ],
              ),
            )
          else if (_failed || _text.text.trim().isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                _failed ? l10n.cantReadImageText : l10n.noImageText,
                key: const Key('image_text_none'),
                textAlign: TextAlign.center,
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.45),
              child: TextField(
                key: const Key('image_text_field'),
                controller: _text,
                textDirection: textDirectionOf(_text.text),
                maxLines: null,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('image_text_copy'),
                  onPressed: hasText ? _copy : null,
                  icon: const Icon(Icons.copy_outlined),
                  label: Text(l10n.copyText),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  key: const Key('image_text_add'),
                  onPressed: hasText ? () => Navigator.of(context).pop(_text.text.trim()) : null,
                  icon: const Icon(Icons.note_add_outlined),
                  label: Text(l10n.addToNote),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
