import '../notes/data/notes_repository.dart';
import '../tags/data/tags_repository.dart';
import 'keep_takeout_parser.dart';

class KeepImportResult {
  const KeepImportResult({
    required this.imported,
    required this.skippedDuplicates,
    required this.skippedTrashed,
    required this.attachmentsNotImported,
  });

  final int imported;
  final int skippedDuplicates;
  final int skippedTrashed;
  final int attachmentsNotImported;
}

/// Writes Google Keep notes into the vault: labels become tags, colours,
/// pins, archive and checklists carry over. Notes already imported (same
/// title, text and creation time) are skipped, so running it twice is safe.
class KeepImporter {
  KeepImporter({required this.notes, required this.tags});

  final NotesRepository notes;
  final TagsRepository tags;

  Future<KeepImportResult> run(List<KeepNote> keepNotes) async {
    final existing = {
      for (final note in await notes.fetchAll())
        _key(note.title, note.body, note.createdAt),
    };
    final tagIds = {
      for (final tag in await tags.fetchAll()) tag.name.toLowerCase(): tag.id,
    };

    var imported = 0;
    var duplicates = 0;
    var trashed = 0;
    var attachments = 0;
    for (final keep in keepNotes) {
      if (keep.trashed) {
        trashed++;
        continue;
      }
      if (keep.isEmpty) continue;
      final createdAt = keep.createdAt ?? keep.editedAt;
      final key = _key(keep.title, keep.body, createdAt);
      if (existing.contains(key)) {
        duplicates++;
        continue;
      }
      final noteTagIds = <String>[];
      for (final label in keep.labels) {
        final id = tagIds[label.toLowerCase()] ??= (await tags.create(label)).id;
        if (!noteTagIds.contains(id)) noteTagIds.add(id);
      }
      await notes.createNote(
        title: keep.title,
        body: keep.body,
        tagIds: noteTagIds,
        pinned: keep.pinned && !keep.archived,
        color: keep.color,
        archived: keep.archived,
        checklist: keep.checklist,
        createdAt: createdAt,
      );
      existing.add(key);
      attachments += keep.attachmentCount;
      imported++;
    }
    return KeepImportResult(
      imported: imported,
      skippedDuplicates: duplicates,
      skippedTrashed: trashed,
      attachmentsNotImported: attachments,
    );
  }

  /// Seconds, because stored dates round-trip through ISO strings.
  static String _key(String title, String body, DateTime? createdAt) =>
      '${title.trim()}\u0000${body.trim()}\u0000${createdAt == null ? '' : createdAt.millisecondsSinceEpoch ~/ 1000}';
}
