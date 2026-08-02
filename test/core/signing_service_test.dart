import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_notes/src/core/crypto/signing_service.dart';

void main() {
  final service = SigningService();

  test('a signature verifies against the message and matching public key', () async {
    final keyMaterial = await service.generateKeyPair();
    final message = Uint8List.fromList(utf8.encode('sync payload contents'));

    final signature = await service.sign(message, keyMaterial);
    final isValid = await service.verify(
      message,
      signatureBytes: signature,
      publicKeyBytes: keyMaterial.publicKeyBytes,
    );

    expect(isValid, isTrue);
  });

  test('verification fails if the message is tampered with after signing', () async {
    final keyMaterial = await service.generateKeyPair();
    final original = Uint8List.fromList(utf8.encode('sync payload contents'));
    final tampered = Uint8List.fromList(utf8.encode('sync payload CONTENTS'));

    final signature = await service.sign(original, keyMaterial);
    final isValid = await service.verify(
      tampered,
      signatureBytes: signature,
      publicKeyBytes: keyMaterial.publicKeyBytes,
    );

    expect(isValid, isFalse);
  });

  test('verification fails against a different device\'s public key', () async {
    final ownerKeyMaterial = await service.generateKeyPair();
    final attackerKeyMaterial = await service.generateKeyPair();
    final message = Uint8List.fromList(utf8.encode('sync payload contents'));

    final signature = await service.sign(message, ownerKeyMaterial);
    final isValid = await service.verify(
      message,
      signatureBytes: signature,
      publicKeyBytes: attackerKeyMaterial.publicKeyBytes,
    );

    expect(isValid, isFalse);
  });
}
