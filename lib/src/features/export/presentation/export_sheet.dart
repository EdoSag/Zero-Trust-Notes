import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../notebooks/application/notebooks_controller.dart';
import '../../notes/application/note_lock.dart';
import '../../notes/application/notes_providers.dart';
import '../../notes/domain/note.dart';
import '../../tags/application/tags_controller.dart';
import '../application/export_service.dart';
import '../application/export_temp_file_registry.dart';
import '../application/markdown_folder_export.dart';
import '../data/export_file_writer.dart';
import '../domain/export_format.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';

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
                widget.singleNote == null ? context.l10n.exportAll : context.l10n.exportThis,
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
          : [
              // Everything but Trash, shared notes included.
              for (final note in await ref.read(notesRepositoryProvider)!.fetchEverything())
                if (!note.isTrashed) note,
            ];

      // Locked notes are written out in full, so the owner confirms first,
      // just as when opening one. (A single note is exported from its
      // editor, which is only open once it's unlocked.)
      final lockedCount = widget.singleNote != null ? 0 : notes.where((n) => n.locked).length;
      if (lockedCount > 0) {
        if (!mounted) return;
        final confirmed = await ref
            .read(noteLockAuthenticatorProvider)
            .confirm(
              context,
              ref,
              reason: lockedCount == 1
                  ? context.l10n.exportLockedOne
                  : context.l10n.exportLockedMany(lockedCount),
            );
        if (!confirmed) {
          if (mounted) {
            setState(
              () => _errorMessage =
                  context.l10n.exportNeedsAuth,
            );
          }
          return;
        }
      }

      final bytes = format == ExportFormat.markdownFolder
          ? await _markdownFolder(notes)
          : await _exportService.render(notes, format);
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
      if (mounted) setState(() => _errorMessage = context.l10n.exportFailed('$error'));
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

/// The Markdown folder, with notebook and tag names and the notes'
/// pictures and files.
extension on _ExportSheetContentState {
  Future<Uint8List> _markdownFolder(List<Note> notes) async {
    final notebooks = await ref.read(notebooksRepositoryProvider)?.fetchAll() ?? const [];
    final tags = await ref.read(tagsRepositoryProvider)?.fetchAll() ?? const [];
    final repository = ref.read(notesRepositoryProvider)!;
    final result = await MarkdownFolderExport.build(
      notes,
      notebookNames: {for (final notebook in notebooks) notebook.id: notebook.name},
      tagNames: {for (final tag in tags) tag.id: tag.name},
      readFile: repository.readImage,
    );
    if (result.missing > 0 && mounted) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(context.l10n.imagesNotHere(result.missing))));
    }
    return result.zip;
  }
}

class _FormatTile extends StatelessWidget {
  const _FormatTile({required this.format, required this.onTap});

  final ExportFormat format;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.l10n.exportAs(_label(context)),
      button: true,
      child: SizedBox(
        height: 48,
        child: ListTile(leading: Icon(_iconFor(format)), title: Text(_label(context)), onTap: onTap),
      ),
    );
  }

  String _label(BuildContext context) =>
      format == ExportFormat.markdownFolder ? context.l10n.exportMarkdownFolder : format.label;

  IconData _iconFor(ExportFormat format) => switch (format) {
    ExportFormat.markdown => Icons.description_outlined,
    ExportFormat.markdownFolder => Icons.folder_zip_outlined,
    ExportFormat.pdf => Icons.picture_as_pdf_outlined,
    ExportFormat.json => Icons.data_object,
  };
}
