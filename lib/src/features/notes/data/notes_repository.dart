import 'dart:async';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../../../shared/watch_store.dart';
import '../../notebooks/domain/notebook.dart';
import '../../sharing/shared_notebooks.dart';
import '../domain/checklist_item.dart';
import '../domain/note.dart';
import '../domain/note_color.dart';

/// Reads notes from the account's encrypted local store and writes them
/// through the shared sync controller, which stores each change locally and
/// pushes it shortly after.
class NotesRepository {
  NotesRepository({
    required this._store,
    required this._sync,
    this._attachments,
    this._shared,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ZtLocalStore _store;

  /// The sync controller, once its engine is open. Saving waits for it, so
  /// an edit made right after unlock isn't refused.
  final Future<SyncController> Function() _sync;
  final DateTime Function() _clock;

  /// Encrypted image storage; null where there is none (some tests).
  final Future<ZtAttachments> Function()? _attachments;

  /// Shared notebooks and notes; null where sharing isn't set up (tests).
  /// A note goes there when its notebook is shared, or when it was shared
  /// on its own.
  final SharedNoteStore? Function()? _shared;

  SharedNoteStore _requireShared() =>
      _shared?.call() ?? (throw StateError("Sharing isn't available right now."));
  static const _uuid = Uuid();

  /// Every note of the account's own store (including archived and
  /// trashed ones), newest first, and again after every change. Shared
  /// notes come from [SharedNoteStore.notes].
  Stream<List<Note>> watchAll() => watchStore(_store, fetchAll);

  /// One-shot read of every note of the account's own store, including
  /// archived and trashed ones.
  Future<List<Note>> fetchAll() async {
    final notes = [
      for (final item in await _store.liveItems())
        if (Note.isNoteJson(item.json)) Note.fromItem(item),
    ];
    return notes..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  /// Own and shared notes together, newest first.
  Future<List<Note>> fetchEverything() async {
    final shared = _shared?.call()?.notes ?? const <Note>[];
    return [...await fetchAll(), ...shared]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  /// The space [note] belongs in: its notebook's, or the one it was shared
  /// on its own in; null for the account's own store.
  String? _homeOf(Note note) {
    final notebookSpace = Notebook.spaceIdOf(note.notebookId);
    if (notebookSpace != null) return notebookSpace;
    final current = note.spaceId;
    if (current != null && (_shared?.call()?.isSingle(current) ?? false)) return current;
    return null;
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
    List<ZtAttachmentRef> images = const [],
    bool locked = false,
    Map<String, ZtAttachmentRef> drawings = const {},
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
      images: images,
      locked: locked,
      drawings: drawings,
    );
    return updateNote(note);
  }

  /// Also brings back a deleted [note]: saving an id again revives it.
  /// Moves it between the account's store and a shared space when its
  /// notebook says so. Returns the note as now stored.
  Future<Note> updateNote(Note note) async {
    final home = _homeOf(note);
    final stored = note.located(home, notebookId: note.notebookId);
    if (home == null) {
      await (await _sync()).save(note.id, stored.toItemJson());
    } else {
      await _requireShared().saveNote(stored);
    }
    if (home != note.spaceId) {
      // Moved: remove the copy it left behind.
      if (note.spaceId == null) {
        await (await _sync()).delete(note.id);
      } else {
        await _requireShared().deleteNote(note);
      }
    }
    return stored;
  }

  /// Moves [note] to Trash, where it stays for [Note.trashRetention]. Its
  /// pin and reminder are dropped, like Keep does.
  Future<Note> moveToTrash(Note note) async {
    final trashed = note.copyWith(trashedAt: _clock().toUtc(), pinned: false, reminderAt: null);
    return updateNote(trashed);
  }

  Future<Note> restoreFromTrash(Note note) => updateNote(note.copyWith(trashedAt: null));

  /// Encrypts [bytes] on this device and stores them for a note: kept
  /// locally at once, uploaded when online. Put the returned ref in the
  /// note's `images`. Throws [AttachmentTooLarge] over the size limit.
  Future<ZtAttachmentRef> addImage(Uint8List bytes, {String? mimeType, String? name}) async {
    final attachments = _attachments;
    if (attachments == null) throw StateError('Image storage is not available');
    return (await attachments()).put(bytes, mimeType: mimeType, name: name);
  }

  /// Encrypts a drawing's strokes for a note, like [addImage].
  Future<ZtAttachmentRef> addFile(Uint8List bytes, {String? mimeType, String? name}) =>
      addImage(bytes, mimeType: mimeType, name: name);

  /// The decrypted image.
  Future<Uint8List> readImage(ZtAttachmentRef image) async {
    final attachments = _attachments;
    if (attachments == null) throw StateError('Image storage is not available');
    return (await attachments()).read(image);
  }

  /// Deletes the stored files of [images] that no note (Trash included)
  /// refers to any more. A conflicted copy shares its images with the
  /// original, so a file goes only when its last note does. Never throws:
  /// a file left behind is better than a failed delete.
  Future<void> releaseImages(Iterable<ZtAttachmentRef> images) async {
    final attachments = _attachments;
    if (attachments == null || images.isEmpty) return;
    try {
      final inUse = {
        for (final note in await fetchEverything())
          for (final file in note.attachments) file.id,
      };
      final unused = [
        for (final image in images)
          if (!inUse.contains(image.id)) image,
      ];
      if (unused.isEmpty) return;
      await (await attachments()).deleteAll(unused);
    } on Object {
      // Locked or storage unavailable: leave the files.
    }
  }

  /// Deletes for good (a tombstone that syncs to every device, or to every
  /// member for a shared note), with its images.
  Future<void> deleteNote(Note note) => _deleteAll([note]);

  Future<void> _deleteAll(List<Note> notes) async {
    if (notes.isEmpty) return;
    final sync = await _sync();
    for (final note in notes) {
      if (note.spaceId == null) {
        await sync.delete(note.id);
      } else {
        await _requireShared().deleteNote(note);
      }
    }
    // Images of shared notes stay: another member's note may show them.
    await releaseImages([
      for (final note in notes)
        if (!note.isShared) ...note.attachments,
    ]);
  }

  /// Deletes every note in Trash for good, shared ones included. Returns
  /// how many.
  Future<int> emptyTrash() async {
    final trashed = (await fetchEverything()).where((note) => note.isTrashed).toList();
    await _deleteAll(trashed);
    return trashed.length;
  }

  /// Deletes notes that have been in Trash longer than [Note.trashRetention].
  Future<int> purgeExpiredTrash() async {
    final now = _clock();
    final expired = (await fetchEverything())
        .where((note) => note.purgeAt != null && !note.purgeAt!.isAfter(now))
        .toList();
    if (expired.isEmpty) return 0;
    await _deleteAll(expired);
    return expired.length;
  }

  /// Shares [notebook] with other people: makes a space for it, moves its
  /// notes there and removes the account's own copy. Locked notes stay
  /// private (the lock is this account's own) and leave the notebook.
  /// Returns the new space's id.
  Future<String> shareNotebook(
    SharedNotesController shared,
    Notebook notebook, {
    required String myName,
  }) async {
    final notes = [
      for (final note in await fetchAll())
        if (note.notebookId == notebook.id) note,
    ];
    final moving = [
      for (final note in notes)
        if (!note.locked) note,
    ];
    final spaceId = await shared.create(name: notebook.name, myName: myName, notes: moving);
    final sync = await _sync();
    for (final note in moving) {
      await sync.delete(note.id);
    }
    for (final note in notes) {
      if (note.locked) {
        await sync.save(note.id, note.copyWith(notebookId: null).toItemJson());
      }
    }
    await sync.delete(notebook.id);
    return spaceId;
  }

  /// Shares one [note] on its own. Returns the new space's id.
  Future<String> shareNote(
    SharedNotesController shared,
    Note note, {
    required String myName,
    required String name,
  }) async {
    if (note.isShared) throw StateError('Already shared');
    final spaceId = await shared.create(
      name: name,
      myName: myName,
      single: true,
      notes: [note.copyWith(notebookId: null)],
    );
    await (await _sync()).delete(note.id);
    return spaceId;
  }
}
