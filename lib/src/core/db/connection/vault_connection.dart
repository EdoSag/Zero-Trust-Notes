import 'package:drift/drift.dart';

export 'vault_connection_stub.dart'
    if (dart.library.io) 'vault_connection_native.dart'
    if (dart.library.js_interop) 'vault_connection_web.dart';

/// Opens the platform-appropriate [QueryExecutor] for the local note vault.
///
/// Native platforms get whole-file encryption (Tier 1) via SQLite3MultipleCiphers
/// keyed with [passphrase]. Web has no whole-file cipher available (WASM sandbox
/// can't run the native cipher engine) — see `vault_connection_web.dart` — so it
/// relies solely on the Tier-2 AES-256-GCM column encryption applied above the
/// database layer, and [passphrase] is ignored there.
typedef OpenVaultConnection = QueryExecutor Function({
  required String passphrase,
  required String fileBaseName,
});
