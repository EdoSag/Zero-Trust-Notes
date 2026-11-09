import 'package:uuid/uuid.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../../../shared/watch_store.dart';
import '../../notes/domain/note.dart';
import '../domain/notebook.dart';

/// Notebooks live in the same encrypted, synced store as notes (see
/// [Notebook]), so they reach every device too.
class NotebooksRepository {
  NotebooksRepository({required this._store, required this._sync});

  final ZtLocalStore _store;
  final Future<SyncController> Function() _sync;
  static const _uuid = Uuid();

  /// The notebooks by name, and again after every change.
  Stream<List<Notebook>> watchAll() => watchStore(_store, fetchAll);

  Future<List<Notebook>> fetchAll() async {
    final notebooks = [
      for (final item in await _store.liveItems())
        if (Notebook.isNotebookJson(item.json)) Notebook.fromItem(item),
    ];
    return notebooks..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<Notebook> create(String name) async {
    final notebook = Notebook(id: _uuid.v4(), name: name);
    await (await _sync()).save(notebook.id, notebook.toItemJson());
    return notebook;
  }

  Future<void> rename(String id, String name) async =>
      (await _sync()).save(id, Notebook(id: id, name: name).toItemJson());

  /// Un-assigns any notes pointing at this notebook before removing it, so
  /// deleting a notebook never leaves a dangling `notebookId` behind.
  Future<void> delete(String id) async {
    final sync = await _sync();
    for (final item in await _store.liveItems()) {
      if (!Note.isNoteJson(item.json)) continue;
      final note = Note.fromItem(item);
      if (note.notebookId == id) await sync.save(note.id, note.copyWith(notebookId: null).toItemJson());
    }
    await sync.delete(id);
  }
}
