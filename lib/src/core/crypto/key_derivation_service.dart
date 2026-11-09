import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

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

  /// Runs on a background isolate: 600k rounds in Dart take seconds on a
  /// phone and would freeze the UI. The web has no isolates, so it runs
  /// inline there.
  Future<Uint8List> derive({required String passphrase, required Uint8List salt}) {
    final nonce = Uint8List.fromList(salt);
    Future<Uint8List> run() async {
      const pbkdf2 = DartPbkdf2(
        macAlgorithm: DartHmac(DartSha256()),
        iterations: iterations,
        bits: keyLengthBytes * 8,
      );
      final secretKey = await pbkdf2.deriveKeyFromPassword(password: passphrase, nonce: nonce);
      return Uint8List.fromList(await secretKey.extractBytes());
    }

    return kIsWeb ? run() : Isolate.run(run);
  }
}
