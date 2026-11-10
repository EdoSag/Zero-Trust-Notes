import 'dart:async';
import 'dart:typed_data';

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
  NotesRepository({
    required this._store,
    required this._sync,
    this._attachments,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ZtLocalStore _store;

  /// The sync controller, once its engine is open. Saving waits for it, so
  /// an edit made right after unlock isn't refused.
  final Future<SyncController> Function() _sync;
  final DateTime Function() _clock;

  /// Encrypted image storage; null where there is none (some tests).
  final Future<ZtAttachments> Function()? _attachments;
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
    List<ZtAttachmentRef> images = const [],
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

  /// Encrypts [bytes] on this device and stores them for a note: kept
  /// locally at once, uploaded when online. Put the returned ref in the
  /// note's `images`. Throws [AttachmentTooLarge] over the size limit.
  Future<ZtAttachmentRef> addImage(Uint8List bytes, {String? mimeType, String? name}) async {
    final attachments = _attachments;
    if (attachments == null) throw StateError('Image storage is not available');
    return (await attachments()).put(bytes, mimeType: mimeType, name: name);
  }

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
        for (final note in await fetchAll())
          for (final image in note.images) image.id,
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

  /// Deletes for good (a tombstone that syncs to every device), with its
  /// images.
  Future<void> deleteNote(String id) => _deleteAll([id]);

  Future<void> _deleteAll(List<String> ids) async {
    if (ids.isEmpty) return;
    final wanted = ids.toSet();
    final images = [
      for (final note in await fetchAll())
        if (wanted.contains(note.id)) ...note.images,
    ];
    final sync = await _sync();
    for (final id in ids) {
      await sync.delete(id);
    }
    await releaseImages(images);
  }

  /// Deletes every note in Trash for good. Returns how many.
  Future<int> emptyTrash() async {
    final trashed = (await fetchAll()).where((note) => note.isTrashed).toList();
    await _deleteAll([for (final note in trashed) note.id]);
    return trashed.length;
  }

  /// Deletes notes that have been in Trash longer than [Note.trashRetention].
  Future<int> purgeExpiredTrash() async {
    final now = _clock();
    final expired = (await fetchAll())
        .where((note) => note.purgeAt != null && !note.purgeAt!.isAfter(now))
        .toList();
    if (expired.isEmpty) return 0;
    await _deleteAll([for (final note in expired) note.id]);
    return expired.length;
  }
}
