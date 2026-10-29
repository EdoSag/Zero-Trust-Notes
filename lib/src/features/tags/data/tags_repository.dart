import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/local_note_vault.dart';

/// Tags (and their note associations) are plaintext organizational metadata,
/// same as [NotebooksRepository] — no cipher step needed here.
class TagsRepository {
  TagsRepository({required LocalNoteVault vault}) : _vault = vault;

  final LocalNoteVault _vault;
  static const _uuid = Uuid();

  Stream<List<Tag>> watchAll() {
    final query = _vault.select(_vault.tags)..orderBy([(row) => OrderingTerm.asc(row.name)]);
    return query.watch();
  }

  Future<Tag> create(String name, {String? colorHex}) async {
    final id = _uuid.v4();
    await _vault.into(_vault.tags).insert(
          TagsCompanion.insert(id: id, name: name, colorHex: Value(colorHex)),
        );
    return Tag(id: id, name: name, colorHex: colorHex);
  }

  Future<void> delete(String id) async {
    await _vault.transaction(() async {
      await (_vault.delete(_vault.noteTags)..where((row) => row.tagId.equals(id))).go();
      await (_vault.delete(_vault.tags)..where((row) => row.id.equals(id))).go();
    });
  }

  Stream<List<String>> watchTagIdsForNote(String noteId) {
    final query = _vault.select(_vault.noteTags)..where((row) => row.noteId.equals(noteId));
    return query.watch().map((rows) => rows.map((row) => row.tagId).toList());
  }

  Future<void> setTagsForNote(String noteId, Set<String> tagIds) async {
    await _vault.transaction(() async {
      await (_vault.delete(_vault.noteTags)..where((row) => row.noteId.equals(noteId))).go();
      for (final tagId in tagIds) {
        await _vault.into(_vault.noteTags).insert(
              NoteTagsCompanion.insert(noteId: noteId, tagId: tagId),
            );
      }
    });
  }
}
