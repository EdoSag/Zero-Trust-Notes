import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_notes/src/core/crypto/key_derivation_service.dart';

void main() {
  const service = KeyDerivationService();

  test('same passphrase and salt deterministically derive the same key', () async {
    final salt = Uint8List.fromList(utf8.encode('0123456789abcdef'));

    final keyA = await service.derive(passphrase: 'correct horse battery staple', salt: salt);
    final keyB = await service.derive(passphrase: 'correct horse battery staple', salt: salt);

    expect(keyA, equals(keyB));
    expect(keyA, hasLength(KeyDerivationService.keyLengthBytes));
  });

  test('a different passphrase derives a different key from the same salt', () async {
    final salt = Uint8List.fromList(utf8.encode('0123456789abcdef'));

    final correct = await service.derive(passphrase: 'correct horse battery staple', salt: salt);
    final wrong = await service.derive(passphrase: 'wrong passphrase', salt: salt);

    expect(correct, isNot(equals(wrong)));
  });

  test('a different salt derives a different key from the same passphrase', () async {
    final saltA = Uint8List.fromList(utf8.encode('0123456789abcdef'));
    final saltB = Uint8List.fromList(utf8.encode('fedcba9876543210'));

    final keyA = await service.derive(passphrase: 'correct horse battery staple', salt: saltA);
    final keyB = await service.derive(passphrase: 'correct horse battery staple', salt: saltB);

    expect(keyA, isNot(equals(keyB)));
  });

  test('generateSalt produces 16 non-deterministic bytes', () {
    final saltA = service.generateSalt();
    final saltB = service.generateSalt();

    expect(saltA, hasLength(KeyDerivationService.saltLengthBytes));
    expect(saltA, isNot(equals(saltB)));
  });

  test('derivation timing for 600,000 PBKDF2-HMAC-SHA256 iterations', () async {
    final salt = service.generateSalt();
    final stopwatch = Stopwatch()..start();
    await service.derive(passphrase: 'correct horse battery staple', salt: salt);
    stopwatch.stop();

    // Not a hard assertion — this test exists to print a number into the
    // test log so unlock-latency UX decisions (M2 risk #7 in the plan) are
    // based on a measurement, not a guess. This machine isn't representative
    // of a low-end Android device or a browser without native acceleration,
    // so treat this as a lower bound, not the real-world number.
    // ignore: avoid_print
    print('PBKDF2 (600,000 iterations) took ${stopwatch.elapsedMilliseconds}ms on this machine');
  });
}
