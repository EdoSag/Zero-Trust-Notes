import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// AES-256-GCM encryption used at two layers: Tier-2 column encryption for
/// note content (via [encrypt]/[decrypt]), and encrypting arbitrary binary
/// payloads — the escrowed Ed25519 private key, whole-vault sync snapshots —
/// via [encryptBytes]/[decryptBytes].
///
/// Produces/consumes a single sealed-box blob: nonce || ciphertext || MAC.
class PayloadCipherService {
  PayloadCipherService({AesGcm? algorithm}) : _algorithm = algorithm ?? AesGcm.with256bits();

  final AesGcm _algorithm;

  Future<Uint8List> encryptBytes(Uint8List plaintext, Uint8List keyBytes) async {
    final secretBox = await _algorithm.encrypt(plaintext, secretKey: SecretKey(keyBytes));
    return Uint8List.fromList(secretBox.concatenation());
  }

  Future<Uint8List> decryptBytes(Uint8List sealedBox, Uint8List keyBytes) async {
    final secretBox = SecretBox.fromConcatenation(
      sealedBox,
      nonceLength: _algorithm.nonceLength,
      macLength: _algorithm.macAlgorithm.macLength,
    );
    final clearBytes = await _algorithm.decrypt(secretBox, secretKey: SecretKey(keyBytes));
    return Uint8List.fromList(clearBytes);
  }

  Future<Uint8List> encrypt(String plaintext, Uint8List keyBytes) {
    return encryptBytes(Uint8List.fromList(utf8.encode(plaintext)), keyBytes);
  }

  Future<String> decrypt(Uint8List sealedBox, Uint8List keyBytes) async {
    return utf8.decode(await decryptBytes(sealedBox, keyBytes));
  }
}
