import 'package:drift/drift.dart';

/// Plaintext organizational metadata. Protected only by the whole-file
/// SQLCipher/SQLite3MultipleCiphers encryption (Tier 1) — note content
/// itself gets a second, column-level layer (see [Notes]/[NoteRevisions]).
class Notebooks extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get colorHex => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class NoteTags extends Table {
  TextColumn get noteId => text()();
  TextColumn get tagId => text()();

  @override
  Set<Column> get primaryKey => {noteId, tagId};
}

/// Tier-2 encryption: `encryptedTitle`/`encryptedBody`/`encryptedAttachments`
/// hold AES-256-GCM sealed boxes (nonce + ciphertext + MAC), produced by
/// `PayloadCipherService` before the row is ever inserted. Drift/SQLite
/// never sees plaintext note content.
@DataClassName('NoteRow')
class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get notebookId => text().nullable().references(Notebooks, #id)();
  BlobColumn get encryptedTitle => blob()();
  BlobColumn get encryptedBody => blob()();
  BlobColumn get encryptedAttachments => blob().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class NoteRevisions extends Table {
  TextColumn get id => text()();
  TextColumn get noteId => text().references(Notes, #id)();
  BlobColumn get encryptedTitle => blob()();
  BlobColumn get encryptedBody => blob()();
  BlobColumn get encryptedAttachments => blob().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Local-only audit trail (unlock attempts, exports, sync events). Never
/// leaves the device.
class AccessLog extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get eventType => text()();
  TextColumn get detail => text().nullable()();
  DateTimeColumn get timestamp => dateTime()();
}

/// Tracks local backup/export operations for later cleanup/audit (export
/// lifecycle management lands in M4; the table exists from M1 so it's
/// covered by Tier-1 encryption from day one).
class BackupHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get sizeBytes => integer()();
  TextColumn get destination => text()();
}
