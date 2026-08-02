import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class VaultProfile {
  const VaultProfile({required this.salt, this.publicKey, this.encryptedPrivateKey});

  final Uint8List salt;
  final Uint8List? publicKey;
  final Uint8List? encryptedPrivateKey;
}

/// Talks to the `profiles` table — shared across every app in this Supabase
/// project — for the columns this app cares about: the per-user KDF salt,
/// and the escrowed Ed25519 keypair (public key in the clear, private key
/// encrypted client-side with the Tier-2 key before it's ever sent here).
///
/// `salt` is a `text` column (base64 in, base64 out). `public_key` and
/// `encrypted_private_key` are `bytea`; PostgREST represents those as
/// `\x`-prefixed hex strings over JSON, which this class encodes/decodes.
class ProfileRepository {
  ProfileRepository({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<VaultProfile?> fetch(String userId) async {
    final row = await _client
        .from('profiles')
        .select('salt, public_key, encrypted_private_key')
        .eq('id', userId)
        .maybeSingle();
    if (row == null) return null;

    final saltText = row['salt'] as String?;
    if (saltText == null) return null;

    return VaultProfile(
      salt: base64Decode(saltText),
      publicKey: _decodeBytea(row['public_key'] as String?),
      encryptedPrivateKey: _decodeBytea(row['encrypted_private_key'] as String?),
    );
  }

  Future<void> upsertSalt(String userId, Uint8List salt) {
    return _client.from('profiles').upsert({'id': userId, 'salt': base64Encode(salt)});
  }

  /// [salt] must be included even though it's presumably already on the
  /// row: Postgres validates NOT NULL constraints against the full
  /// candidate row for `INSERT ... ON CONFLICT DO UPDATE` *before*
  /// arbitrating the conflict, so an upsert payload that omits a NOT NULL
  /// column (like `profiles.salt`) fails even when it would only ever take
  /// the UPDATE branch.
  Future<void> upsertKeyMaterial(
    String userId, {
    required Uint8List salt,
    required Uint8List publicKey,
    required Uint8List encryptedPrivateKey,
  }) {
    return _client.from('profiles').upsert({
      'id': userId,
      'salt': base64Encode(salt),
      'public_key': _encodeBytea(publicKey),
      'encrypted_private_key': _encodeBytea(encryptedPrivateKey),
    });
  }

  static Uint8List? _decodeBytea(String? pgHexLiteral) {
    if (pgHexLiteral == null) return null;
    final hexDigits = pgHexLiteral.startsWith('\\x') ? pgHexLiteral.substring(2) : pgHexLiteral;
    final bytes = Uint8List(hexDigits.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hexDigits.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  static String _encodeBytea(Uint8List bytes) {
    final buffer = StringBuffer('\\x');
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
