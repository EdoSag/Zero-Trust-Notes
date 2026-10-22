import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../errors/vault_exceptions.dart';
import 'connection/vault_connection.dart';
import 'tables.dart';

part 'local_note_vault.g.dart';

/// Fail-closed entry point to the local encrypted vault.
///
/// [open] never returns a database that hasn't proven it's actually
/// encrypted (native) or, on web, that at least came up cleanly under the
/// reduced-security posture. Any doubt throws [VaultInitializationException]
/// and the caller must treat the vault as still locked.
@DriftDatabase(
  tables: [Notebooks, Tags, NoteTags, Notes, NoteRevisions, AccessLog, BackupHistory, SyncMeta],
)
class LocalNoteVault extends _$LocalNoteVault {
  LocalNoteVault._(super.executor);

  @visibleForTesting
  LocalNoteVault.forTesting(super.executor);

  /// The vault file Notes used on the shared account before it moved onto
  /// the core's local store. Only ever opened to move its notes over (see
  /// `movePreviousNotesStore`).
  static const currentFileBaseName = 'notes_v2';

  /// The pre-core vault, keyed by the old vault passphrase. Only ever
  /// opened to import its notes (see `LegacyNotesImporter`).
  static const legacyFileBaseName = 'note_vault';

  static Future<LocalNoteVault> open({
    required String passphrase,
    String fileBaseName = 'note_vault',
  }) async {
    final vault = LocalNoteVault._(
      openVaultConnection(passphrase: passphrase, fileBaseName: fileBaseName),
    );
    await vault._ensureVaultIntegrity();
    return vault;
  }

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(notes, notes.isDirty);
            await m.addColumn(notes, notes.updatedAtMicros);
            await m.createTable(syncMeta);
          }
        },
      );

  /// Forces the connection to actually open (native: spawns the background
  /// isolate and runs the `PRAGMA key` setup callback) and surfaces any
  /// failure — wrong passphrase, corrupted file, or a cipher engine that
  /// didn't report an active cipher — as a single, consistent exception
  /// instead of letting it leak out lazily on whatever query happens first.
  Future<void> _ensureVaultIntegrity() async {
    try {
      await customSelect('SELECT 1').getSingleOrNull();
    } catch (error) {
      await close();
      throw VaultInitializationException(
        'Local vault failed its fail-closed integrity check; refusing to '
        'proceed with a database that might be unencrypted or opened with '
        'the wrong passphrase. Cause: $error',
      );
    }
  }
}
