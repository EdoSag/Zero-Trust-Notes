import 'dart:async';

import 'package:uuid/uuid.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../../../shared/watch_store.dart';
import '../domain/note.dart';

/// Reads notes from the account's encrypted local store and writes them
/// through the shared sync controller, which stores each change locally and
/// pushes it shortly after.
class NotesRepository {
  NotesRepository({required this._store, required this._sync});

  final ZtLocalStore _store;

  /// The sync controller, once its engine is open. Saving waits for it, so
  /// an edit made right after unlock isn't refused.
  final Future<SyncController> Function() _sync;
  static const _uuid = Uuid();

  /// The current notes, newest first, and again after every change.
  Stream<List<Note>> watchAll() => watchStore(_store, fetchAll);

  /// One-shot read for callers (export) that just need the current list.
  Future<List<Note>> fetchAll() async {
    final notes = [
      for (final item in await _store.liveItems())
        if (Note.isNoteJson(item.json)) Note.fromItem(item),
    ];
    return notes..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<Note> createNote({
    required String title,
    required String body,
    String? notebookId,
    List<String> tagIds = const [],
  }) async {
    final now = DateTime.now().toUtc();
    final id = _uuid.v4();
    await (await _sync()).save(
      id,
      Note.itemJson(title: title, body: body, notebookId: notebookId, tagIds: tagIds, createdAt: now),
    );
    return Note(
      id: id,
      notebookId: notebookId,
      title: title,
      body: body,
      createdAt: now,
      updatedAt: now,
      tagIds: tagIds,
    );
  }

  /// Also brings back a deleted [note]: saving an id again revives it.
  Future<void> updateNote(Note note) async => (await _sync()).save(note.id, note.toItemJson());

  Future<void> deleteNote(String id) async => (await _sync()).delete(id);
}
