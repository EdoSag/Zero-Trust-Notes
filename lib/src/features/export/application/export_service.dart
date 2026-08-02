import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../../notes/domain/note.dart';
import '../domain/export_format.dart';

/// Renders decrypted notes into exportable bytes. Content only exists in
/// memory here — where those bytes end up (a real temp file on native, an
/// in-memory `XFile` on web) is handled by `export_file_writer.dart`.
class ExportService {
  const ExportService();

  Future<Uint8List> render(List<Note> notes, ExportFormat format) {
    return switch (format) {
      ExportFormat.markdown => _renderMarkdown(notes),
      ExportFormat.json => _renderJson(notes),
      ExportFormat.pdf => _renderPdf(notes),
    };
  }

  String suggestedFileName(ExportFormat format, {String? singleNoteTitle}) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final base = singleNoteTitle != null
        ? _sanitizeFileNameComponent(singleNoteTitle)
        : 'zerotrust_notes_export';
    return '${base}_$timestamp.${format.fileExtension}';
  }

  String mimeTypeFor(ExportFormat format) => switch (format) {
        ExportFormat.markdown => 'text/markdown',
        ExportFormat.json => 'application/json',
        ExportFormat.pdf => 'application/pdf',
      };

  Future<Uint8List> _renderMarkdown(List<Note> notes) async {
    final buffer = StringBuffer('# Zero-Trust Notes Export\n\n')
      ..writeln('Exported ${DateTime.now().toUtc().toIso8601String()}')
      ..writeln();

    for (final note in notes) {
      buffer
        ..writeln('## ${note.title.isEmpty ? '(untitled)' : note.title}')
        ..writeln()
        ..writeln(note.body)
        ..writeln()
        ..writeln('_Updated: ${note.updatedAt.toIso8601String()}_')
        ..writeln()
        ..writeln('---')
        ..writeln();
    }

    return Uint8List.fromList(utf8.encode(buffer.toString()));
  }

  Future<Uint8List> _renderJson(List<Note> notes) async {
    final payload = {
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'notes': notes
          .map((note) => {
                'id': note.id,
                'title': note.title,
                'body': note.body,
                'createdAt': note.createdAt.toIso8601String(),
                'updatedAt': note.updatedAt.toIso8601String(),
              })
          .toList(),
    };
    return Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)));
  }

  Future<Uint8List> _renderPdf(List<Note> notes) async {
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Header(level: 0, text: 'Zero-Trust Notes Export'),
          pw.Text(
            'Exported ${DateTime.now().toUtc().toIso8601String()}',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.SizedBox(height: 16),
          for (final note in notes) ...[
            pw.Header(level: 1, text: note.title.isEmpty ? '(untitled)' : note.title),
            pw.Paragraph(text: note.body),
            pw.Text(
              'Updated: ${note.updatedAt.toIso8601String()}',
              style: const pw.TextStyle(fontSize: 8),
            ),
            pw.SizedBox(height: 12),
          ],
        ],
      ),
    );
    return document.save();
  }

  String _sanitizeFileNameComponent(String value) {
    final sanitized = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9\-_ ]'), '').replaceAll(' ', '_');
    return sanitized.isEmpty ? 'note' : sanitized;
  }
}
