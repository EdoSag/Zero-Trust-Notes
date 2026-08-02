import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../errors/vault_exceptions.dart';

/// Opens a SQLite3MultipleCiphers-encrypted [NativeDatabase] backed by a file
/// in the app documents directory. `PRAGMA key` runs inside the `setup`
/// callback so it executes before drift (or any caller) can issue a single
/// query — if the cipher engine doesn't report an active cipher afterwards,
/// this throws [VaultInitializationException] instead of silently returning
/// a database that turned out to be unencrypted.
QueryExecutor openVaultConnection({
  required String passphrase,
  required String fileBaseName,
}) {
  return DatabaseConnection.delayed(Future(() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final file = File(p.join(documentsDir.path, '$fileBaseName.sqlite'));

    final executor = NativeDatabase.createInBackground(
      file,
      setup: (rawDb) {
        rawDb.execute("PRAGMA key = ${_sqlQuote(passphrase)};");

        final cipherRows = rawDb.select('PRAGMA cipher;');
        if (cipherRows.isEmpty) {
          throw VaultInitializationException(
            'PRAGMA cipher returned no active cipher after PRAGMA key; '
            'refusing to open what may be an unencrypted database.',
          );
        }
      },
    );

    return DatabaseConnection(executor);
  }));
}

String _sqlQuote(String value) => "'${value.replaceAll("'", "''")}'";
