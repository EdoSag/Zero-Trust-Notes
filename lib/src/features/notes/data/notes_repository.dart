import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../../../core/crypto/payload_cipher_service.dart';
import '../../../core/db/local_note_vault.dart';
import '../../sync/data/notes_item_store.dart';
import '../domain/note.dart';

/// Reads notes from [LocalNoteVault] and writes them through the shared
/// sync engine, so every change is encrypted, stored locally, and queued
/// for sync in one step. Nothing plaintext ever touches the database.
class NotesRepository {
  NotesRepository({
    required this._vault,
    required this._columnKey,
    required this._engine,
    this._onChanged,
    PayloadCipherService? cipher,
  }) : _cipher = cipher ?? PayloadCipherService();

  final LocalNoteVault _vault;
  final Uint8List _columnKey;
  final ItemSyncEngine _engine;
  final void Function()? _onChanged;
  final PayloadCipherService _cipher;
  static const _uuid = Uuid();

  Stream<List<Note>> watchAll() => _liveQuery().watch().asyncMap(_decryptAll);

  /// One-shot read for callers (export) that just need the current list
  /// once rather than a live stream.
  Future<List<Note>> fetchAll() async => _decryptAll(await _liveQuery().get());

  SimpleSelectStatement<$NotesTable, NoteRow> _liveQuery() => _vault.select(_vault.notes)
    ..where((row) => row.isDeleted.equals(false))
    ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]);

  Future<List<Note>> _decryptAll(List<NoteRow> rows) async {
    final notes = <Note>[];
    for (final row in rows) {
      notes.add(
        Note(
          id: row.id,
          notebookId: row.notebookId,
          title: await _cipher.decrypt(row.encryptedTitle, _columnKey),
          body: await _cipher.decrypt(row.encryptedBody, _columnKey),
          createdAt: row.createdAt,
          updatedAt: row.updatedAt,
        ),
      );
    }
    return notes;
  }

  Future<Note> createNote({required String title, required String body}) async {
    final now = DateTime.now().toUtc();
    final id = _uuid.v4();
    await _engine.save(id, NotesItemStore.noteJson(title: title, body: body, createdAt: now));
    _onChanged?.call();
    return Note(id: id, notebookId: null, title: title, body: body, createdAt: now, updatedAt: now);
  }

  Future<void> updateNote(Note note) async {
    await _engine.save(
      note.id,
      NotesItemStore.noteJson(
        title: note.title,
        body: note.body,
        notebookId: note.notebookId,
        createdAt: note.createdAt,
      ),
    );
    _onChanged?.call();
  }

  Future<void> deleteNote(String id) async {
    await _engine.delete(id);
    _onChanged?.call();
  }
}
