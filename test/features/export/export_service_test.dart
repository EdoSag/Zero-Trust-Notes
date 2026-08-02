import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_notes/src/features/export/application/export_service.dart';
import 'package:zerotrust_notes/src/features/export/domain/export_format.dart';
import 'package:zerotrust_notes/src/features/notes/domain/note.dart';

void main() {
  const service = ExportService();

  List<Note> sampleNotes() => [
        Note(
          id: 'note-1',
          notebookId: null,
          title: 'First note',
          body: 'First body',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 2),
        ),
        Note(
          id: 'note-2',
          notebookId: null,
          title: 'Second note',
          body: 'Second body',
          createdAt: DateTime.utc(2026, 1, 3),
          updatedAt: DateTime.utc(2026, 1, 4),
        ),
      ];

  test('markdown export contains every note title and body', () async {
    final bytes = await service.render(sampleNotes(), ExportFormat.markdown);
    final text = utf8.decode(bytes);

    expect(text, contains('First note'));
    expect(text, contains('First body'));
    expect(text, contains('Second note'));
    expect(text, contains('Second body'));
  });

  test('json export round-trips note fields exactly', () async {
    final bytes = await service.render(sampleNotes(), ExportFormat.json);
    final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final notes = decoded['notes'] as List<dynamic>;

    expect(notes, hasLength(2));
    expect(notes[0]['id'], 'note-1');
    expect(notes[0]['title'], 'First note');
    expect(notes[0]['body'], 'First body');
    expect(notes[1]['id'], 'note-2');
  });

  test('pdf export produces a well-formed PDF document', () async {
    final bytes = await service.render(sampleNotes(), ExportFormat.pdf);

    // PDF files start with the "%PDF-" magic header.
    expect(utf8.decode(bytes.take(5).toList()), '%PDF-');
    expect(bytes.length, greaterThan(100));
  });

  test('an empty note list still produces valid, empty-ish output per format', () async {
    for (final format in ExportFormat.values) {
      final bytes = await service.render(const [], format);
      expect(bytes, isNotEmpty);
    }
  });

  test('suggestedFileName uses the export format extension', () {
    expect(service.suggestedFileName(ExportFormat.markdown), endsWith('.md'));
    expect(service.suggestedFileName(ExportFormat.pdf), endsWith('.pdf'));
    expect(service.suggestedFileName(ExportFormat.json), endsWith('.json'));
  });

  test('suggestedFileName sanitizes a single note title for use as a filename', () {
    final fileName = service.suggestedFileName(
      ExportFormat.markdown,
      singleNoteTitle: 'My Note: "Ideas" / Draft?',
    );

    expect(fileName, isNot(contains(':')));
    expect(fileName, isNot(contains('/')));
    expect(fileName, isNot(contains('"')));
    expect(fileName, isNot(contains('?')));
  });
}
