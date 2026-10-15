import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

class VaultProfile {
  const VaultProfile({required this.salt, this.publicKey, this.encryptedPrivateKey});

  final Uint8List salt;
  final Uint8List? publicKey;
  final Uint8List? encryptedPrivateKey;
}

/// Read-only view of the pre-core `profiles` columns, used once to import
/// notes written before Notes moved onto the shared account.
///
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
      // Sibling apps wrote this salt in several base64 dialects.
      salt: ZtBase64.decode(saltText),
      publicKey: _decodeBytea(row['public_key'] as String?),
      encryptedPrivateKey: _decodeBytea(row['encrypted_private_key'] as String?),
    );
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
}
