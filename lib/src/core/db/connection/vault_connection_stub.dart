import 'package:drift/drift.dart';

/// Reached only if neither `dart.library.io` nor `dart.library.js_interop`
/// is available for the current compile target.
QueryExecutor openVaultConnection({
  required String passphrase,
  required String fileBaseName,
}) {
  throw UnsupportedError(
    'No local vault connection implementation for this platform.',
  );
}
