import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Derives the symmetric key used for Tier-2 AES-256-GCM column encryption
/// from the user's vault master passphrase, via PBKDF2-HMAC-SHA256 with
/// 600,000 iterations over a per-user random salt.
///
/// The salt isn't secret — it's a KDF parameter, not a key — so it's safe to
/// persist as-is and (from M3 onward) mirror to `profiles.salt` for
/// cross-device re-derivation. What must never leave the device is the
/// passphrase itself and the derived key.
class KeyDerivationService {
  const KeyDerivationService();

  static const int iterations = 600000;
  static const int keyLengthBytes = 32;
  static const int saltLengthBytes = 16;

  Uint8List generateSalt() {
    final random = Random.secure();
    return Uint8List.fromList(List<int>.generate(saltLengthBytes, (_) => random.nextInt(256)));
  }

  Future<Uint8List> derive({required String passphrase, required Uint8List salt}) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: keyLengthBytes * 8,
    );
    final secretKey = await pbkdf2.deriveKeyFromPassword(password: passphrase, nonce: salt);
    final bytes = await secretKey.extractBytes();
    return Uint8List.fromList(bytes);
  }
}
