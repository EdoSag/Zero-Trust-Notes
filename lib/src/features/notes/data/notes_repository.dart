import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/crypto/payload_cipher_service.dart';
import '../../../core/db/local_note_vault.dart';
import '../domain/note.dart';

/// Reads/writes notes through the Tier-2 cipher: nothing plaintext ever
/// touches [LocalNoteVault].
class NotesRepository {
  NotesRepository({
    required LocalNoteVault vault,
    required Uint8List payloadKeyBytes,
    PayloadCipherService? cipher,
  })  : _vault = vault,
        _payloadKeyBytes = payloadKeyBytes,
        _cipher = cipher ?? PayloadCipherService();

  final LocalNoteVault _vault;
  final Uint8List _payloadKeyBytes;
  final PayloadCipherService _cipher;
  static const _uuid = Uuid();

  Stream<List<Note>> watchAll() {
    final query = _vault.select(_vault.notes)
      ..where((row) => row.isDeleted.equals(false))
      ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]);
    return query.watch().asyncMap(_decryptAll);
  }

  /// One-shot read for callers (export) that just need the current list
  /// once rather than a live stream.
  Future<List<Note>> fetchAll() async {
    final query = _vault.select(_vault.notes)
      ..where((row) => row.isDeleted.equals(false))
      ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]);
    return _decryptAll(await query.get());
  }

  Future<List<Note>> _decryptAll(List<NoteRow> rows) async {
    final notes = <Note>[];
    for (final row in rows) {
      notes.add(await _decryptRow(row));
    }
    return notes;
  }

  Future<Note> _decryptRow(NoteRow row) async {
    final title = await _cipher.decrypt(row.encryptedTitle, _payloadKeyBytes);
    final body = await _cipher.decrypt(row.encryptedBody, _payloadKeyBytes);
    return Note(
      id: row.id,
      notebookId: row.notebookId,
      title: title,
      body: body,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  Future<Note> createNote({required String title, required String body, String? notebookId}) async {
    final now = DateTime.now().toUtc();
    final id = _uuid.v4();
    final encryptedTitle = await _cipher.encrypt(title, _payloadKeyBytes);
    final encryptedBody = await _cipher.encrypt(body, _payloadKeyBytes);

    await _vault.into(_vault.notes).insert(
          NotesCompanion.insert(
            id: id,
            notebookId: Value(notebookId),
            encryptedTitle: encryptedTitle,
            encryptedBody: encryptedBody,
            createdAt: now,
            updatedAt: now,
          ),
        );

    return Note(
      id: id,
      notebookId: notebookId,
      title: title,
      body: body,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> updateNote(Note note) async {
    final now = DateTime.now().toUtc();
    final encryptedTitle = await _cipher.encrypt(note.title, _payloadKeyBytes);
    final encryptedBody = await _cipher.encrypt(note.body, _payloadKeyBytes);

    await (_vault.update(_vault.notes)..where((row) => row.id.equals(note.id))).write(
      NotesCompanion(
        notebookId: Value(note.notebookId),
        encryptedTitle: Value(encryptedTitle),
        encryptedBody: Value(encryptedBody),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> restoreNote(String id) async {
    await (_vault.update(_vault.notes)..where((row) => row.id.equals(id))).write(
      const NotesCompanion(isDeleted: Value(false)),
    );
  }

  Future<void> deleteNote(String id) async {
    await (_vault.update(_vault.notes)..where((row) => row.id.equals(id))).write(
      const NotesCompanion(isDeleted: Value(true)),
    );
  }
}
