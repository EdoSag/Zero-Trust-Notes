import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../notes/application/notes_providers.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';

/// One decrypted note image, cropped to fill its box. Shows a spinner while
/// it decrypts (or downloads), and a plain placeholder when it can't be
/// read, such as an image another device added but hasn't uploaded yet.
class NoteImage extends ConsumerWidget {
  const NoteImage({super.key, required this.image, this.fit = BoxFit.cover, this.cacheWidth});

  final ZtAttachmentRef image;
  final BoxFit fit;

  /// Decode at this width (physical pixels) to save memory in thumbnails.
  final int? cacheWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return switch (ref.watch(noteImageProvider(image))) {
      AsyncData(:final value) => Image.memory(
        value,
        fit: fit,
        cacheWidth: cacheWidth,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _Placeholder(icon: Icons.broken_image_outlined, scheme: scheme),
      ),
      AsyncError(:final error) => _Placeholder(
        icon: error is AttachmentNotFound
            ? Icons.cloud_download_outlined
            : Icons.broken_image_outlined,
        scheme: scheme,
      ),
      _ => ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: const Center(
          child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
    };
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.icon, required this.scheme});

  final IconData icon;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: scheme.surfaceContainerHighest,
    child: Center(child: Icon(icon, color: scheme.onSurfaceVariant)),
  );
}

/// The images at the top of the editor: a row of thumbnails, tap one to
/// see it full size.
class NoteImageStrip extends StatelessWidget {
  const NoteImageStrip({super.key, required this.images, required this.onOpen, this.height = 112});

  final List<ZtAttachmentRef> images;
  final void Function(int index) onOpen;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cacheWidth = (height * MediaQuery.devicePixelRatioOf(context) * 2).round();
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) => Semantics(
          button: true,
          label: context.l10n.imageNofM(index + 1, images.length),
          hint: context.l10n.opensImage,
          excludeSemantics: true,
          child: ClipRRect(
            key: ValueKey('note_image_${images[index].id}'),
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: height * 1.25,
              child: Material(
                child: InkWell(
                  onTap: () => onOpen(index),
                  child: Ink(
                    child: NoteImage(image: images[index], cacheWidth: cacheWidth),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen images of one note: swipe between them, pinch to zoom.
/// [onRemove] (absent for a note in Trash) removes the shown one; the
/// viewer closes when the last one goes.
class NoteImageViewer extends StatefulWidget {
  const NoteImageViewer({
    super.key,
    required this.images,
    this.initialIndex = 0,
    this.onRemove,
    this.onShare,
    this.onGrabText,
    this.onEditDrawing,
    this.isDrawing,
  });

  final List<ZtAttachmentRef> images;
  final int initialIndex;
  final Future<void> Function(ZtAttachmentRef image)? onRemove;
  final Future<void> Function(ZtAttachmentRef image)? onShare;

  /// Reads the text in the shown image (the viewer closes first).
  final void Function(ZtAttachmentRef image)? onGrabText;

  /// Opens the shown drawing for editing (the viewer closes first).
  final void Function(ZtAttachmentRef image)? onEditDrawing;
  final bool Function(ZtAttachmentRef image)? isDrawing;

  @override
  State<NoteImageViewer> createState() => _NoteImageViewerState();
}

class _NoteImageViewerState extends State<NoteImageViewer> {
  late final List<ZtAttachmentRef> _images = [...widget.images];
  late final PageController _controller = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.removeImageQ),
        content: Text(context.l10n.removeImageBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.remove),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final image = _images[_index];
    await widget.onRemove!(image);
    if (!mounted) return;
    // By id, not position: the page may have been swiped meanwhile.
    setState(() {
      _images.removeWhere((i) => i.id == image.id);
      if (_index >= _images.length) _index = _images.length - 1;
    });
    if (_images.isEmpty) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark(useMaterial3: true),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: Text(_images.length > 1 ? context.l10n.nOfM(_index + 1, _images.length) : context.l10n.image),
          actions: [
            if (widget.onEditDrawing != null &&
                _images.isNotEmpty &&
                (widget.isDrawing?.call(_images[_index]) ?? false))
              IconButton(
                key: const Key('image_viewer_edit_drawing'),
                tooltip: context.l10n.editDrawing,
                icon: const Icon(Icons.draw_outlined),
                onPressed: () {
                  final image = _images[_index];
                  Navigator.of(context).pop();
                  widget.onEditDrawing!(image);
                },
              ),
            if (widget.onGrabText != null && _images.isNotEmpty)
              IconButton(
                key: const Key('image_viewer_grab_text'),
                tooltip: context.l10n.grabImageText,
                icon: const Icon(Icons.document_scanner_outlined),
                onPressed: () {
                  final image = _images[_index];
                  Navigator.of(context).pop();
                  widget.onGrabText!(image);
                },
              ),
            if (widget.onShare != null && _images.isNotEmpty)
              IconButton(
                tooltip: context.l10n.sendImage,
                icon: const Icon(Icons.share_outlined),
                onPressed: () => widget.onShare!(_images[_index]),
              ),
            if (widget.onRemove != null && _images.isNotEmpty)
              IconButton(
                tooltip: context.l10n.removeImage,
                icon: const Icon(Icons.delete_outline),
                onPressed: _remove,
              ),
          ],
        ),
        body: PageView.builder(
          controller: _controller,
          itemCount: _images.length,
          onPageChanged: (index) => setState(() => _index = index),
          itemBuilder: (context, index) => InteractiveViewer(
            maxScale: 5,
            child: Center(
              child: Semantics(
                image: true,
                label: context.l10n.imageNofM(index + 1, _images.length),
                child: NoteImage(image: _images[index], fit: BoxFit.contain),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
