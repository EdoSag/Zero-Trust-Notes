import 'package:drift/drift.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../../../core/crypto/payload_cipher_service.dart';
import '../../../core/db/local_note_vault.dart';

/// The shared sync engine's view of the local `notes` table.
///
/// A sync item is one note as JSON (`title`, `body`, `notebookId`,
/// `createdAt`). Title and body stay Tier-2 encrypted at rest under
/// [columnKey]; this store is the only place that seals and opens them.
class NotesItemStore implements LocalItemStore {
  NotesItemStore({required this._vault, required this._columnKey, PayloadCipherService? cipher})
    : _cipher = cipher ?? PayloadCipherService();

  final LocalNoteVault _vault;
  final Uint8List _columnKey;
  final PayloadCipherService _cipher;

  static const _lastPulledKey = 'last_pulled_at';

  @override
  Future<LocalItem?> get(String itemId) async {
    final row = await (_vault.select(
      _vault.notes,
    )..where((n) => n.id.equals(itemId))).getSingleOrNull();
    return row == null ? null : _toItem(row);
  }

  @override
  Future<List<LocalItem>> all() async {
    final rows = await _vault.select(_vault.notes).get();
    return [for (final row in rows) await _toItem(row)];
  }

  @override
  Future<void> put(LocalItem item) async {
    final json = item.json;
    final title = (json?['title'] as String?) ?? '';
    final body = (json?['body'] as String?) ?? '';
    final createdAt = json?['createdAt'] == null
        ? item.updatedAt
        : DateTime.parse(json!['createdAt'] as String);
    await _vault
        .into(_vault.notes)
        .insertOnConflictUpdate(
          NotesCompanion.insert(
            id: item.itemId,
            notebookId: Value(json?['notebookId'] as String?),
            encryptedTitle: await _cipher.encrypt(title, _columnKey),
            encryptedBody: await _cipher.encrypt(body, _columnKey),
            createdAt: createdAt.toUtc(),
            updatedAt: item.updatedAt.toUtc(),
            isDeleted: Value(item.deleted),
            isDirty: Value(item.dirty),
            updatedAtMicros: Value(item.updatedAt.microsecondsSinceEpoch),
          ),
        );
  }

  @override
  Future<DateTime?> lastPulledAt() async {
    final row = await (_vault.select(
      _vault.syncMeta,
    )..where((m) => m.key.equals(_lastPulledKey))).getSingleOrNull();
    return row == null ? null : DateTime.parse(row.value);
  }

  @override
  Future<void> setLastPulledAt(DateTime value) => _vault
      .into(_vault.syncMeta)
      .insertOnConflictUpdate(
        SyncMetaCompanion.insert(key: _lastPulledKey, value: value.toUtc().toIso8601String()),
      );

  Future<LocalItem> _toItem(NoteRow row) async => LocalItem(
    itemId: row.id,
    updatedAt: _updatedAt(row),
    deleted: row.isDeleted,
    dirty: row.isDirty,
    json: row.isDeleted
        ? null
        : {
            'title': await _cipher.decrypt(row.encryptedTitle, _columnKey),
            'body': await _cipher.decrypt(row.encryptedBody, _columnKey),
            'notebookId': row.notebookId,
            'createdAt': row.createdAt.toUtc().toIso8601String(),
          },
  );

  static DateTime _updatedAt(NoteRow row) => row.updatedAtMicros == null
      ? row.updatedAt.toUtc()
      : DateTime.fromMicrosecondsSinceEpoch(row.updatedAtMicros!, isUtc: true);

  /// The JSON shape of one note.
  static Map<String, Object?> noteJson({
    required String title,
    required String body,
    String? notebookId,
    required DateTime createdAt,
  }) => {
    'title': title,
    'body': body,
    'notebookId': notebookId,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
}
