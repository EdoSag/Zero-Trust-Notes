import 'dart:async';

import 'package:uuid/uuid.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../../../shared/watch_store.dart';
import '../domain/checklist_item.dart';
import '../domain/note.dart';
import '../domain/note_color.dart';

/// Reads notes from the account's encrypted local store and writes them
/// through the shared sync controller, which stores each change locally and
/// pushes it shortly after.
class NotesRepository {
  NotesRepository({required this._store, required this._sync, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final ZtLocalStore _store;

  /// The sync controller, once its engine is open. Saving waits for it, so
  /// an edit made right after unlock isn't refused.
  final Future<SyncController> Function() _sync;
  final DateTime Function() _clock;
  static const _uuid = Uuid();

  /// Every note (including archived and trashed ones), newest first, and
  /// again after every change.
  Stream<List<Note>> watchAll() => watchStore(_store, fetchAll);

  /// One-shot read of every note, including archived and trashed ones.
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
    bool pinned = false,
    NoteColor color = NoteColor.none,
    bool archived = false,
    List<ChecklistItem>? checklist,
    DateTime? reminderAt,
    DateTime? createdAt,
  }) async {
    final now = _clock().toUtc();
    final note = Note(
      id: _uuid.v4(),
      notebookId: notebookId,
      title: title,
      body: body,
      createdAt: createdAt?.toUtc() ?? now,
      updatedAt: now,
      tagIds: tagIds,
      pinned: pinned,
      color: color,
      archived: archived,
      checklist: checklist,
      reminderAt: reminderAt,
    );
    await (await _sync()).save(note.id, note.toItemJson());
    return note;
  }

  /// Also brings back a deleted [note]: saving an id again revives it.
  Future<void> updateNote(Note note) async => (await _sync()).save(note.id, note.toItemJson());

  /// Moves [note] to Trash, where it stays for [Note.trashRetention]. Its
  /// pin and reminder are dropped, like Keep does.
  Future<Note> moveToTrash(Note note) async {
    final trashed = note.copyWith(trashedAt: _clock().toUtc(), pinned: false, reminderAt: null);
    await updateNote(trashed);
    return trashed;
  }

  Future<Note> restoreFromTrash(Note note) async {
    final restored = note.copyWith(trashedAt: null);
    await updateNote(restored);
    return restored;
  }

  /// Deletes for good (a tombstone that syncs to every device).
  Future<void> deleteNote(String id) async => (await _sync()).delete(id);

  /// Deletes every note in Trash for good. Returns how many.
  Future<int> emptyTrash() async {
    final trashed = (await fetchAll()).where((note) => note.isTrashed).toList();
    final sync = await _sync();
    for (final note in trashed) {
      await sync.delete(note.id);
    }
    return trashed.length;
  }

  /// Deletes notes that have been in Trash longer than [Note.trashRetention].
  Future<int> purgeExpiredTrash() async {
    final now = _clock();
    final expired = (await fetchAll())
        .where((note) => note.purgeAt != null && !note.purgeAt!.isAfter(now))
        .toList();
    if (expired.isEmpty) return 0;
    final sync = await _sync();
    for (final note in expired) {
      await sync.delete(note.id);
    }
    return expired.length;
  }
}
