import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/local_note_vault.dart';

/// Notebooks are plaintext organizational metadata (Tier-1 whole-file
/// encryption only, see [Notebooks] table doc) — no cipher step needed here,
/// unlike [NotesRepository].
class NotebooksRepository {
  NotebooksRepository({required LocalNoteVault vault}) : _vault = vault;

  final LocalNoteVault _vault;
  static const _uuid = Uuid();

  Stream<List<Notebook>> watchAll() {
    final query = _vault.select(_vault.notebooks)
      ..orderBy([(row) => OrderingTerm.asc(row.name)]);
    return query.watch();
  }

  Future<Notebook> create(String name) async {
    final now = DateTime.now().toUtc();
    final id = _uuid.v4();
    await _vault.into(_vault.notebooks).insert(
          NotebooksCompanion.insert(id: id, name: name, createdAt: now, updatedAt: now),
        );
    return Notebook(id: id, name: name, createdAt: now, updatedAt: now);
  }

  Future<void> rename(String id, String name) async {
    await (_vault.update(_vault.notebooks)..where((row) => row.id.equals(id))).write(
      NotebooksCompanion(name: Value(name), updatedAt: Value(DateTime.now().toUtc())),
    );
  }

  /// Un-assigns any notes pointing at this notebook before removing it, so
  /// deleting a notebook never leaves a dangling `notebookId` behind.
  Future<void> delete(String id) async {
    await _vault.transaction(() async {
      await (_vault.update(_vault.notes)..where((row) => row.notebookId.equals(id))).write(
        const NotesCompanion(notebookId: Value(null)),
      );
      await (_vault.delete(_vault.notebooks)..where((row) => row.id.equals(id))).go();
    });
  }
}
