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
import '../notes/domain/note.dart';
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
/// account. They were encrypted with a separate vault passphrase, which the
/// user types once; the shared [LegacyImporter] then saves them under the
/// account, dated before any real edit so a newer version from another
/// device always wins, and records that the import is done. The old file is
/// left in place, untouched apart from a schema upgrade.
class LegacyNotesImporter {
  LegacyNotesImporter({
    required this.sources,
    required this._engine,
    required this._ledger,
    required this._deriveKey,
  });

  /// Reads the old notes of [userId] (salt from this device or the profile).
  LegacyNotesImporter.forUser(
    String userId, {
    required List<LegacyNotesSource> sources,
    required ItemSyncEngine engine,
    required LegacyImportLedger ledger,
  }) : this(
         sources: sources,
         engine: engine,
         ledger: ledger,
         deriveKey: (passphrase) => _legacyKey(userId, passphrase),
       );

  /// The shared import ledger's name for this data.
  static const source = 'notes-vault-v1';

  final List<LegacyNotesSource> sources;
  final ItemSyncEngine _engine;
  final LegacyImportLedger _ledger;
  final Future<Uint8List?> Function(String passphrase) _deriveKey;

  Future<bool> isDone() => _ledger.legacyImportDone(source);

  /// The first source that has data, or null when there's nothing to import.
  Future<LegacyNotesSource?> pendingSource() async {
    if (await isDone()) return null;
    for (final s in sources) {
      try {
        if (await s.exists()) return s;
      } on Object {
        // Offline or no access: try the next source, ask again next unlock.
      }
    }
    return null;
  }

  /// Returns how many notes were imported. Throws [WrongLegacyPassphrase]
  /// (and imports nothing) when [passphrase] doesn't open the old notes.
  Future<int> run(String passphrase) async {
    final pending = await pendingSource();
    if (pending == null) return 0;
    // Null when the account never had a salt, so there can't be old notes.
    final oldKey = await _deriveKey(passphrase);
    try {
      final result = await LegacyImporter(
        source: source,
        read: (_) async => [
          for (final note in await pending.read(passphrase))
            LegacyRecord(
              itemId: note.id,
              json: Note.itemJson(
                title: note.title,
                body: note.body,
                notebookId: note.notebookId,
                createdAt: note.createdAt,
              ),
            ),
        ],
      ).run(engine: _engine, ledger: _ledger, legacyKey: oldKey);
      return result.imported;
    } finally {
      oldKey?.fillRange(0, oldKey.length, 0);
    }
  }
}
