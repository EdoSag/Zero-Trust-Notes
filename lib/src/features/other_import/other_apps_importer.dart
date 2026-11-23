import 'package:zero_trust_core/zero_trust_core.dart';

import '../notebooks/data/notebooks_repository.dart';
import '../notes/data/notes_repository.dart';
import '../notes/domain/checklist_item.dart';
import '../tags/data/tags_repository.dart';
import 'imported_note.dart';

class OtherAppsImportResult {
  const OtherAppsImportResult({
    required this.imported,
    required this.skippedDuplicates,
    required this.skippedTrashed,
    required this.filesNotAdded,
  });

  final int imported;
  final int skippedDuplicates;
  final int skippedTrashed;

  /// Pictures and files over 20 MB, or that couldn't be stored.
  final int filesNotAdded;
}

/// Saves notes read from other apps (N-1): tags and notebooks are matched
/// by name or made, pictures and files are encrypted like any attachment.
/// A note already in Notes (same title, text and creation time) is
/// skipped, so importing the same export twice is safe. Notes are saved
/// one at a time, and the core spaces out a long run of saves, so a big
/// import doesn't freeze the app.
class OtherAppsImporter {
  OtherAppsImporter({required this.notes, required this.tags, required this.notebooks});

  final NotesRepository notes;
  final TagsRepository tags;
  final NotebooksRepository? notebooks;

  Future<OtherAppsImportResult> run(
    List<ImportedNote> imported, {
    void Function(int done, int total)? onProgress,
  }) async {
    // A note from an export without dates matches on its title and text.
    final existing = {
      for (final note in await notes.fetchAll()) ...[
        _key(note.title, note.body, note.createdAt),
        _key(note.title, note.body, null),
      ],
    };
    final tagIds = {for (final tag in await tags.fetchAll()) tag.name.toLowerCase(): tag.id};
    final notebookIds = {
      for (final notebook in await notebooks?.fetchAll() ?? const [])
        notebook.name.toLowerCase(): notebook.id,
    };

    var saved = 0;
    var duplicates = 0;
    var trashed = 0;
    var filesNotAdded = 0;
    for (final (index, note) in imported.indexed) {
      onProgress?.call(index, imported.length);
      if (note.trashed) {
        trashed++;
        continue;
      }
      if (note.isEmpty) continue;
      final checklist = note.checklist == null ? null : ChecklistItem.ordered(note.checklist!);
      final body = checklist == null ? note.body : ChecklistItem.toMarkdown(checklist);
      final key = _key(note.title, body, note.createdAt);
      if (existing.contains(key)) {
        duplicates++;
        continue;
      }
      final noteTagIds = <String>[];
      for (final name in note.tags) {
        if (name.trim().isEmpty) continue;
        final id = tagIds[name.trim().toLowerCase()] ??= (await tags.create(name.trim())).id;
        if (!noteTagIds.contains(id)) noteTagIds.add(id);
      }
      String? notebookId;
      final notebookName = note.notebook?.trim();
      if (notebookName != null && notebookName.isNotEmpty && notebooks != null) {
        notebookId = notebookIds[notebookName.toLowerCase()] ??= (await notebooks!.create(
          notebookName,
        )).id;
      }
      final images = <ZtAttachmentRef>[];
      final files = <ZtAttachmentRef>[];
      for (final file in note.files) {
        try {
          if (file.isImage) {
            images.add(await notes.addImage(file.bytes, mimeType: file.mimeType, name: file.name));
          } else {
            files.add(await notes.addFile(file.bytes, mimeType: file.mimeType, name: file.name));
          }
        } on Object {
          filesNotAdded++;
        }
      }
      await notes.createNote(
        title: note.title,
        body: body,
        notebookId: notebookId,
        tagIds: noteTagIds,
        pinned: note.pinned && !note.archived,
        archived: note.archived,
        checklist: checklist,
        images: images,
        files: files,
        createdAt: note.createdAt,
      );
      existing
        ..add(key)
        ..add(_key(note.title, body, null));
      saved++;
    }
    onProgress?.call(imported.length, imported.length);
    return OtherAppsImportResult(
      imported: saved,
      skippedDuplicates: duplicates,
      skippedTrashed: trashed,
      filesNotAdded: filesNotAdded,
    );
  }

  /// Seconds, because stored dates round-trip through ISO strings.
  static String _key(String title, String body, DateTime? createdAt) =>
      '${title.trim()}\u0000${body.trim()}\u0000'
      '${createdAt == null ? '' : createdAt.millisecondsSinceEpoch ~/ 1000}';
}
