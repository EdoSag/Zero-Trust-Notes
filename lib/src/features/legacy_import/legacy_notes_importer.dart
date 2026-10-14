import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../../core/crypto/key_derivation_service.dart';
import '../../core/crypto/payload_cipher_service.dart';
import '../../core/db/local_note_vault.dart';
import '../../core/errors/vault_exceptions.dart';
import '../../core/storage/secure_credentials_store.dart';
import '../sync/data/notes_item_store.dart';
import 'legacy_notes_api.dart';
import 'legacy_profile_repository.dart';
import 'legacy_snapshot_codec.dart';

/// The old vault passphrase didn't open the old notes.
class WrongLegacyPassphrase implements Exception {
  const WrongLegacyPassphrase();
}

/// A note as the pre-core app stored it, after decryption.
class LegacyNote {
  const LegacyNote({
    required this.id,
    required this.title,
    required this.body,
    required this.notebookId,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String body;
  final String? notebookId;
  final DateTime createdAt;
}

/// Where pre-core notes can be: the old local vault file, or (on a device
/// that never had it) the old whole-vault cloud snapshot.
abstract interface class LegacyNotesSource {
  Future<bool> exists();

  /// Throws [WrongLegacyPassphrase] when [passphrase] doesn't open it.
  Future<List<LegacyNote>> read(String passphrase);
}

/// Decrypts the live (not deleted) rows of an old vault database.
@visibleForTesting
Future<List<LegacyNote>> decryptLegacyRows(
  List<NoteRow> rows,
  Uint8List oldKey, {
  PayloadCipherService? cipher,
}) async {
  final c = cipher ?? PayloadCipherService();
  final notes = <LegacyNote>[];
  for (final row in rows.where((r) => !r.isDeleted)) {
    try {
      notes.add(
        LegacyNote(
          id: row.id,
          title: await c.decrypt(row.encryptedTitle, oldKey),
          body: await c.decrypt(row.encryptedBody, oldKey),
          notebookId: row.notebookId,
          createdAt: row.createdAt,
        ),
      );
    } on Object {
      throw const WrongLegacyPassphrase();
    }
  }
  return notes;
}

/// Old key = PBKDF2(old vault passphrase, salt), exactly as Notes derived it.
Future<Uint8List?> _legacyKey(String userId, String passphrase) async {
  final salt =
      await SecureCredentialsStore().readSalt(userId) ??
      (await ProfileRepository().fetch(userId))?.salt;
  if (salt == null) return null;
  return const KeyDerivationService().derive(passphrase: passphrase, salt: salt);
}

class LocalFileLegacySource implements LegacyNotesSource {
  LocalFileLegacySource(this.userId);
  final String userId;

  @override
  Future<bool> exists() async {
    if (kIsWeb) return false;
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, '${LocalNoteVault.legacyFileBaseName}.sqlite')).exists();
  }

  @override
  Future<List<LegacyNote>> read(String passphrase) async {
    final LocalNoteVault old;
    try {
      old = await LocalNoteVault.open(
        passphrase: passphrase,
        fileBaseName: LocalNoteVault.legacyFileBaseName,
      );
    } on VaultInitializationException {
      throw const WrongLegacyPassphrase();
    }
    try {
      final key = await _legacyKey(userId, passphrase);
      if (key == null) return const [];
      return await decryptLegacyRows(await old.select(old.notes).get(), key);
    } finally {
      await old.close();
    }
  }
}

class CloudSnapshotLegacySource implements LegacyNotesSource {
  CloudSnapshotLegacySource(this.userId);
  final String userId;

  @override
  Future<bool> exists() async => await EncryptedNotesApi().pull(userId) != null;

  @override
  Future<List<LegacyNote>> read(String passphrase) async {
    final snapshot = await EncryptedNotesApi().pull(userId);
    final profile = await ProfileRepository().fetch(userId);
    final publicKey = profile?.publicKey;
    if (snapshot == null || publicKey == null) return const [];
    final key = await _legacyKey(userId, passphrase);
    if (key == null) return const [];
    final List<NoteRow> rows;
    try {
      rows = await VaultSnapshotCodec().verifyAndDecode(
        dataBlobBase64: snapshot.dataBlobBase64,
        payloadKeyBytes: key,
        trustedPublicKeyBytes: publicKey,
      );
    } on SnapshotIntegrityException {
      rethrow; // tampered or forged: never import
    } on Object {
      throw const WrongLegacyPassphrase();
    }
    return decryptLegacyRows(rows, key);
  }
}

/// One-time move of notes written before Notes used the shared Zero-Trust
/// account. They were encrypted with a separate vault passphrase; this
/// re-encrypts them under the account and queues them for sync. The old
/// file is left in place, untouched apart from a schema upgrade.
class LegacyNotesImporter {
  LegacyNotesImporter({required this.sources, required this._vault, required this._engine});

  final List<LegacyNotesSource> sources;
  final LocalNoteVault _vault;
  final ItemSyncEngine _engine;

  static const _doneKey = 'legacy_import_done_at';

  Future<bool> isDone() async =>
      await (_vault.select(
        _vault.syncMeta,
      )..where((m) => m.key.equals(_doneKey))).getSingleOrNull() !=
      null;

  /// The first source that has data, or null when there's nothing to import.
  Future<LegacyNotesSource?> pendingSource() async {
    if (await isDone()) return null;
    for (final source in sources) {
      try {
        if (await source.exists()) return source;
      } on Object {
        // Offline or no access: try the next source, ask again next unlock.
      }
    }
    return null;
  }

  /// Returns how many notes were imported.
  Future<int> run(String passphrase) async {
    final source = await pendingSource();
    if (source == null) return 0;
    final notes = await source.read(passphrase);
    var imported = 0;
    for (final note in notes) {
      // A note already synced from another device that imported first keeps
      // its newer version; re-saving would only duplicate work.
      if (await _engine.store.get(note.id) != null) continue;
      await _engine.save(
        note.id,
        NotesItemStore.noteJson(
          title: note.title,
          body: note.body,
          notebookId: note.notebookId,
          createdAt: note.createdAt,
        ),
      );
      imported++;
    }
    await markDone();
    return imported;
  }

  Future<void> markDone() => _vault
      .into(_vault.syncMeta)
      .insertOnConflictUpdate(
        SyncMetaCompanion.insert(key: _doneKey, value: DateTime.now().toUtc().toIso8601String()),
      );
}
