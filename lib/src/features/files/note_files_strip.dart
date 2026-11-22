import 'package:flutter/material.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';

/// Whether [file] is a PDF (by type, or by name when the type is missing).
bool isPdf(ZtAttachmentRef file) =>
    file.mimeType == 'application/pdf' || (file.name?.toLowerCase().endsWith('.pdf') ?? false);

/// 1.2 MB, 340 KB.
String fileSize(int bytes) {
  if (bytes >= 1000 * 1000) return '${(bytes / 1000 / 1000).toStringAsFixed(1)} MB';
  if (bytes >= 1000) return '${(bytes / 1000).round()} KB';
  return '$bytes B';
}

IconData fileIcon(ZtAttachmentRef file) {
  final type = file.mimeType ?? '';
  if (isPdf(file)) return Icons.picture_as_pdf_outlined;
  if (type.startsWith('audio/')) return Icons.audio_file_outlined;
  if (type.startsWith('video/')) return Icons.video_file_outlined;
  if (type.startsWith('text/')) return Icons.description_outlined;
  if (type.contains('zip') || type.contains('compressed')) return Icons.folder_zip_outlined;
  return Icons.insert_drive_file_outlined;
}

/// The files attached to a note (PDFs and other documents), as chips with
/// their name and size. Tap to open.
class NoteFilesStrip extends StatelessWidget {
  const NoteFilesStrip({super.key, required this.files, required this.onOpen});

  final List<ZtAttachmentRef> files;
  final void Function(ZtAttachmentRef file) onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final file in files)
          ActionChip(
            key: ValueKey('note_file_${file.id}'),
            avatar: Icon(fileIcon(file), size: 18),
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                '${file.name ?? l10n.attachedFile} · ${fileSize(file.size)}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            tooltip: l10n.openFile(file.name ?? l10n.attachedFile),
            onPressed: () => onOpen(file),
          ),
      ],
    );
  }
}
