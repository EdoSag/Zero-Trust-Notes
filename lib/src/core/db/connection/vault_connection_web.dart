import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

/// Web has no whole-file cipher: SQLite3MultipleCiphers/SQLCipher are native
/// code that can't run inside the browser's WASM sandbox. [passphrase] is
/// intentionally unused here — Tier-2 AES-256-GCM column encryption (applied
/// above this layer, see `PayloadCipherService`) is the only protection notes
/// get on web. The unlock UI must disclose this reduced posture explicitly.
QueryExecutor openVaultConnection({
  required String passphrase,
  required String fileBaseName,
}) {
  return DatabaseConnection.delayed(Future(() async {
    final result = await WasmDatabase.open(
      databaseName: fileBaseName,
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.dart.js'),
    );
    return result.resolvedExecutor;
  }));
}
