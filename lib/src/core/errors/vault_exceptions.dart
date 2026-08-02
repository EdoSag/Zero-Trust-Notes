/// Thrown when the local encrypted database fails to prove it is actually
/// encrypted. The vault must never fall back to an unencrypted database, so
/// any doubt here halts startup instead of degrading silently.
class VaultInitializationException implements Exception {
  VaultInitializationException(this.message);

  final String message;

  @override
  String toString() => 'VaultInitializationException: $message';
}

/// Thrown when a vault unlock attempt fails (wrong passphrase, corrupted
/// key material, etc.).
class VaultUnlockException implements Exception {
  VaultUnlockException(this.message);

  final String message;

  @override
  String toString() => 'VaultUnlockException: $message';
}
