import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Exercises the same PRAGMA key / PRAGMA cipher mechanism that
/// `vault_connection_native.dart` uses, directly against `package:sqlite3`,
/// so the fail-closed guarantee is verified independently of Flutter's
/// widget bindings (path_provider needs a platform channel that plain
/// `flutter test` doesn't provide).
void main() {
  late Directory tempDir;
  late String dbPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('zerotrust_notes_vault_test');
    dbPath = p.join(tempDir.path, 'test_vault.sqlite');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('PRAGMA cipher reports an active cipher after PRAGMA key', () {
    final db = sqlite3.open(dbPath);
    db.execute("PRAGMA key = 'correct horse battery staple';");

    final cipherRows = db.select('PRAGMA cipher;');
    expect(cipherRows, isNotEmpty);

    db.execute('CREATE TABLE notes (id TEXT PRIMARY KEY, body TEXT);');
    db.close();
  });

  test('fails closed: an encrypted file cannot be read without any key', () {
    final writer = sqlite3.open(dbPath);
    writer.execute("PRAGMA key = 'correct horse battery staple';");
    writer.execute('CREATE TABLE notes (id TEXT PRIMARY KEY, body TEXT);');
    writer.execute("INSERT INTO notes VALUES ('1', 'top secret contents');");
    writer.close();

    final reader = sqlite3.open(dbPath);
    expect(
      () => reader.select('SELECT * FROM notes;'),
      throwsA(isA<SqliteException>()),
    );
    reader.close();
  });

  test('fails closed: an encrypted file cannot be read with the wrong passphrase', () {
    final writer = sqlite3.open(dbPath);
    writer.execute("PRAGMA key = 'correct horse battery staple';");
    writer.execute('CREATE TABLE notes (id TEXT PRIMARY KEY, body TEXT);');
    writer.execute("INSERT INTO notes VALUES ('1', 'top secret contents');");
    writer.close();

    final reader = sqlite3.open(dbPath);
    reader.execute("PRAGMA key = 'wrong passphrase';");
    expect(
      () => reader.select('SELECT * FROM notes;'),
      throwsA(isA<SqliteException>()),
    );
    reader.close();
  });
}
