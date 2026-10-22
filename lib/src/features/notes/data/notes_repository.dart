import 'dart:async';

import 'package:uuid/uuid.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

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
  Stream<List<Note>> watchAll() {
    late final StreamController<List<Note>> controller;
    StreamSubscription<Set<String>>? changes;
    Future<void> emit() async {
      try {
        final notes = await fetchAll();
        if (!controller.isClosed) controller.add(notes);
      } catch (e, s) {
        if (!controller.isClosed) controller.addError(e, s);
      }
    }

    controller = StreamController<List<Note>>(
      onListen: () {
        // Listen before the first read, so no change falls in between.
        changes = _store.changes.listen((_) => emit());
        emit();
      },
      onCancel: () => changes?.cancel(),
    );
    return controller.stream;
  }

  /// One-shot read for callers (export) that just need the current list.
  Future<List<Note>> fetchAll() async {
    final notes = [for (final item in await _store.liveItems()) Note.fromItem(item)];
    return notes..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<Note> createNote({required String title, required String body}) async {
    final now = DateTime.now().toUtc();
    final id = _uuid.v4();
    await (await _sync()).save(id, Note.itemJson(title: title, body: body, createdAt: now));
    return Note(id: id, notebookId: null, title: title, body: body, createdAt: now, updatedAt: now);
  }

  Future<void> updateNote(Note note) async => (await _sync()).save(note.id, note.toItemJson());

  Future<void> deleteNote(String id) async => (await _sync()).delete(id);
}
