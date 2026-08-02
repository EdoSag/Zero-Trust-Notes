import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../notes/application/notes_controller.dart';
import '../../notes/domain/note.dart';
import '../application/export_service.dart';
import '../application/export_temp_file_registry.dart';
import '../data/export_file_writer.dart';
import '../domain/export_format.dart';

/// Opens a sheet letting the user export either every note ([singleNote]
/// null) or just one ([singleNote] set) as Markdown, PDF, or JSON, then
/// hands the result to the OS share sheet.
Future<void> showExportSheet(BuildContext context, {Note? singleNote}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ExportSheetContent(singleNote: singleNote),
  );
}

class _ExportSheetContent extends ConsumerStatefulWidget {
  const _ExportSheetContent({this.singleNote});

  final Note? singleNote;

  @override
  ConsumerState<_ExportSheetContent> createState() => _ExportSheetContentState();
}

class _ExportSheetContentState extends ConsumerState<_ExportSheetContent> {
  static const _exportService = ExportService();

  bool _isExporting = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                widget.singleNote == null ? 'Export all notes' : 'Export this note',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 12),
            if (_isExporting)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              for (final format in ExportFormat.values)
                _FormatTile(format: format, onTap: () => _export(format)),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _export(ExportFormat format) async {
    setState(() {
      _isExporting = true;
      _errorMessage = null;
    });

    final registry = ref.read(exportTempFileRegistryProvider);
    String? tempPath;
    var succeeded = false;

    try {
      final notes = widget.singleNote != null
          ? [widget.singleNote!]
          : await ref.read(notesRepositoryProvider)!.fetchAll();

      final bytes = await _exportService.render(notes, format);
      final fileName = _exportService.suggestedFileName(
        format,
        singleNoteTitle: widget.singleNote?.title,
      );

      final (xFile, path) = await writeExportFile(
        bytes: bytes,
        fileName: fileName,
        mimeType: _exportService.mimeTypeFor(format),
      );
      tempPath = path;
      if (tempPath != null) registry.register(tempPath);

      await SharePlus.instance.share(ShareParams(files: [xFile], subject: fileName));
      succeeded = true;
    } catch (error) {
      if (mounted) setState(() => _errorMessage = 'Export failed: $error');
    } finally {
      if (tempPath != null) {
        registry.unregister(tempPath);
        await deleteExportFile(tempPath);
      }
      if (mounted) setState(() => _isExporting = false);
      if (succeeded && mounted) Navigator.of(context).pop();
    }
  }
}

class _FormatTile extends StatelessWidget {
  const _FormatTile({required this.format, required this.onTap});

  final ExportFormat format;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Export as ${format.label}',
      button: true,
      child: SizedBox(
        height: 48,
        child: ListTile(
          leading: Icon(_iconFor(format)),
          title: Text(format.label),
          onTap: onTap,
        ),
      ),
    );
  }

  IconData _iconFor(ExportFormat format) => switch (format) {
        ExportFormat.markdown => Icons.description_outlined,
        ExportFormat.pdf => Icons.picture_as_pdf_outlined,
        ExportFormat.json => Icons.data_object,
      };
}
