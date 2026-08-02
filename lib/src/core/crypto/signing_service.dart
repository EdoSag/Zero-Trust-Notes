import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Raw Ed25519 key bytes, held separately from `SimpleKeyPair` so callers
/// can persist/reload them via secure storage without pulling in the
/// `cryptography` package's key-pair abstractions everywhere.
class Ed25519KeyMaterial {
  const Ed25519KeyMaterial({required this.privateKeyBytes, required this.publicKeyBytes});

  final Uint8List privateKeyBytes;
  final Uint8List publicKeyBytes;
}

/// On-device Ed25519 identity used to sign sync payloads (M3) so Supabase
/// can be treated as an untrusted blob store: the server enforces row
/// ownership, but only a valid signature from this device's key proves the
/// blob's content wasn't tampered with in transit or at rest.
///
/// The private key never leaves the device — it's generated here, stored in
/// `flutter_secure_storage` by the caller, and only ever used locally to
/// sign outgoing payloads.
class SigningService {
  SigningService({Ed25519? algorithm}) : _algorithm = algorithm ?? Ed25519();

  final Ed25519 _algorithm;

  Future<Ed25519KeyMaterial> generateKeyPair() async {
    final keyPair = await _algorithm.newKeyPair();
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
    final publicKey = await keyPair.extractPublicKey();
    return Ed25519KeyMaterial(
      privateKeyBytes: Uint8List.fromList(privateKeyBytes),
      publicKeyBytes: Uint8List.fromList(publicKey.bytes),
    );
  }

  Future<Uint8List> sign(Uint8List message, Ed25519KeyMaterial keyMaterial) async {
    final keyPair = SimpleKeyPairData(
      keyMaterial.privateKeyBytes,
      publicKey: SimplePublicKey(keyMaterial.publicKeyBytes, type: KeyPairType.ed25519),
      type: KeyPairType.ed25519,
    );
    final signature = await _algorithm.sign(message, keyPair: keyPair);
    return Uint8List.fromList(signature.bytes);
  }

  Future<bool> verify(
    Uint8List message, {
    required Uint8List signatureBytes,
    required Uint8List publicKeyBytes,
  }) {
    final signature = Signature(
      signatureBytes,
      publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
    );
    return _algorithm.verify(message, signature: signature);
  }
}
