import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../../core/crypto/payload_cipher_service.dart';
import '../../core/db/local_note_vault.dart';
import '../../core/errors/vault_exceptions.dart';
import 'legacy_notes_importer.dart';

/// The Drift database Notes kept between moving onto the shared account and
/// moving onto the shared local store (`notes_v2.sqlite`).
abstract interface class PreviousNotesStoreFile {
  Future<bool> exists();

  /// Throws [VaultInitializationException] when [key] doesn't open it.
  Future<LocalNoteVault> open(String key);

  Future<void> delete();
}

class DocumentsPreviousNotesStoreFile implements PreviousNotesStoreFile {
  Future<String> _path() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, '${LocalNoteVault.currentFileBaseName}.sqlite');
  }

  @override
  Future<bool> exists() async => !kIsWeb && await File(await _path()).exists();

  @override
  Future<LocalNoteVault> open(String key) =>
      LocalNoteVault.open(passphrase: key, fileBaseName: LocalNoteVault.currentFileBaseName);

  @override
  Future<void> delete() async {
    final path = await _path();
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      final f = File('$path$suffix');
      if (await f.exists()) await f.delete();
    }
  }
}

/// Moves the notes in [PreviousNotesStoreFile] into [store], once per
/// account, keeping each note's edit time and whether it still has to be
/// uploaded, so edits that never reached the server aren't lost. A note the
/// store already has in a newer version is left alone.
///
/// Run it before the first sync after unlock. The old file is deleted once
/// its notes are in [store]. A file this account's key can't open belongs to
/// another account on the device and is left for that account.
///
/// Returns how many notes were moved.
Future<int> movePreviousNotesStore({
  required ZtLocalStore store,
  required Uint8List appKey,
  required PreviousNotesStoreFile file,
  PayloadCipherService? cipher,
}) async {
  const source = 'notes-v2-store';
  if (await store.legacyImportDone(source)) return 0;
  if (!await file.exists()) {
    await store.markLegacyImportDone(source);
    return 0;
  }

  // The keys this file was written under (see the old `notesSessionProvider`).
  final dbKey = await Kdf.hkdf(appKey, 'zt/notes/db/v1');
  final columnKey = await Kdf.hkdf(appKey, 'zt/notes/columns/v1');
  final c = cipher ?? PayloadCipherService();
  var moved = 0;
  try {
    final LocalNoteVault old;
    try {
      old = await file.open(_hex(dbKey));
    } on VaultInitializationException {
      await store.markLegacyImportDone(source);
      return 0;
    }
    try {
      for (final row in await old.select(old.notes).get()) {
        final item = LocalItem(
          itemId: row.id,
          updatedAt: row.updatedAtMicros == null
              ? row.updatedAt.toUtc()
              : DateTime.fromMicrosecondsSinceEpoch(row.updatedAtMicros!, isUtc: true),
          deleted: row.isDeleted,
          dirty: row.isDirty,
          json: row.isDeleted
              ? null
              : {
                  'title': await c.decrypt(row.encryptedTitle, columnKey),
                  'body': await c.decrypt(row.encryptedBody, columnKey),
                  'notebookId': row.notebookId,
                  'createdAt': row.createdAt.toUtc().toIso8601String(),
                },
        );
        final existing = await store.get(item.itemId);
        if (existing != null && !item.updatedAt.isAfter(existing.updatedAt)) continue;
        await store.put(item);
        moved++;
      }
      // The pre-core import already ran on this device: don't offer it again.
      final importDone = await (old.select(
        old.syncMeta,
      )..where((m) => m.key.equals('legacy_import_done_at'))).getSingleOrNull();
      if (importDone != null) {
        await store.markLegacyImportDone(LegacyNotesImporter.source);
      }
    } finally {
      await old.close();
    }
  } finally {
    dbKey.fillRange(0, dbKey.length, 0);
    columnKey.fillRange(0, columnKey.length, 0);
  }
  await store.markLegacyImportDone(source);
  await file.delete();
  return moved;
}

String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
