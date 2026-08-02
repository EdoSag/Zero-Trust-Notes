import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Thin wrapper around flutter_secure_storage for the small set of
/// long-lived secrets the vault needs.
///
/// The salt, Ed25519 keypair, and last-sync timestamp are all keyed by
/// `userId` — if this device is ever signed into more than one Supabase
/// account, each account gets its own cached copies rather than silently
/// reusing whichever user unlocked first. The device id is the one thing
/// that's genuinely device-scoped, not user-scoped.
class SecureCredentialsStore {
  SecureCredentialsStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _deviceIdKey = 'vault_device_id';

  Future<Uint8List?> readSalt(String userId) => _readBytes(_saltKey(userId));
  Future<void> writeSalt(String userId, Uint8List salt) =>
      _writeBytes(_saltKey(userId), salt);

  Future<Uint8List?> readEd25519PrivateKey(String userId) =>
      _readBytes(_ed25519PrivateKeyKey(userId));
  Future<void> writeEd25519PrivateKey(String userId, Uint8List bytes) =>
      _writeBytes(_ed25519PrivateKeyKey(userId), bytes);

  Future<Uint8List?> readEd25519PublicKey(String userId) =>
      _readBytes(_ed25519PublicKeyKey(userId));
  Future<void> writeEd25519PublicKey(String userId, Uint8List bytes) =>
      _writeBytes(_ed25519PublicKeyKey(userId), bytes);

  Future<DateTime?> readLastSyncTimestamp(String userId) async {
    final value = await _storage.read(key: _lastSyncTimestampKey(userId));
    if (value == null) return null;
    return DateTime.parse(value);
  }

  Future<void> writeLastSyncTimestamp(String userId, DateTime timestamp) {
    return _storage.write(
      key: _lastSyncTimestampKey(userId),
      value: timestamp.toUtc().toIso8601String(),
    );
  }

  /// Returns the stable id for this install, generating and persisting one
  /// on first call. Intentionally not user-scoped.
  Future<String> ensureDeviceId() async {
    final existing = await _storage.read(key: _deviceIdKey);
    if (existing != null) return existing;

    final generated = const Uuid().v4();
    await _storage.write(key: _deviceIdKey, value: generated);
    return generated;
  }

  static String _saltKey(String userId) => 'vault_kdf_salt:$userId';
  static String _ed25519PrivateKeyKey(String userId) => 'vault_ed25519_private_key:$userId';
  static String _ed25519PublicKeyKey(String userId) => 'vault_ed25519_public_key:$userId';
  static String _lastSyncTimestampKey(String userId) => 'vault_last_sync_timestamp:$userId';

  Future<Uint8List?> _readBytes(String key) async {
    final encoded = await _storage.read(key: key);
    if (encoded == null) return null;
    return base64Decode(encoded);
  }

  Future<void> _writeBytes(String key, Uint8List bytes) {
    return _storage.write(key: key, value: base64Encode(bytes));
  }
}
