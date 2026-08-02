import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_notes/src/core/crypto/signing_service.dart';
import 'package:zerotrust_notes/src/core/db/local_note_vault.dart';
import 'package:zerotrust_notes/src/features/sync/data/vault_snapshot_codec.dart';

void main() {
  final codec = VaultSnapshotCodec();
  final signing = SigningService();

  Uint8List fixedPayloadKey() => Uint8List.fromList(List.generate(32, (i) => i));

  NoteRow buildRow(String id, {bool isDeleted = false}) => NoteRow(
        id: id,
        notebookId: null,
        encryptedTitle: Uint8List.fromList([1, 2, 3, 4, 5]),
        encryptedBody: Uint8List.fromList([6, 7, 8, 9, 10, 11]),
        encryptedAttachments: null,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 2),
        isDeleted: isDeleted,
      );

  test('encode then decode round-trips the same note rows', () async {
    final payloadKeyBytes = fixedPayloadKey();
    final signingKeyMaterial = await signing.generateKeyPair();
    final rows = [buildRow('note-1'), buildRow('note-2', isDeleted: true)];

    final blob = await codec.encodeAndSign(
      noteRows: rows,
      payloadKeyBytes: payloadKeyBytes,
      signingKeyMaterial: signingKeyMaterial,
    );

    final decoded = await codec.verifyAndDecode(
      dataBlobBase64: blob,
      payloadKeyBytes: payloadKeyBytes,
      trustedPublicKeyBytes: signingKeyMaterial.publicKeyBytes,
    );

    expect(decoded, hasLength(2));
    expect(decoded[0].id, 'note-1');
    expect(decoded[0].encryptedTitle, rows[0].encryptedTitle);
    expect(decoded[0].encryptedBody, rows[0].encryptedBody);
    expect(decoded[0].isDeleted, isFalse);
    expect(decoded[1].id, 'note-2');
    expect(decoded[1].isDeleted, isTrue);
  });

  test('rejects a blob signed by a different key (forged/tampered)', () async {
    final payloadKeyBytes = fixedPayloadKey();
    final signingKeyMaterial = await signing.generateKeyPair();
    final attackerKeyMaterial = await signing.generateKeyPair();
    final rows = [buildRow('note-1')];

    final blob = await codec.encodeAndSign(
      noteRows: rows,
      payloadKeyBytes: payloadKeyBytes,
      signingKeyMaterial: signingKeyMaterial,
    );

    expect(
      () => codec.verifyAndDecode(
        dataBlobBase64: blob,
        payloadKeyBytes: payloadKeyBytes,
        trustedPublicKeyBytes: attackerKeyMaterial.publicKeyBytes,
      ),
      throwsA(isA<SnapshotIntegrityException>()),
    );
  });

  test('rejects a blob whose bytes were altered after signing', () async {
    final payloadKeyBytes = fixedPayloadKey();
    final signingKeyMaterial = await signing.generateKeyPair();
    final rows = [buildRow('note-1')];

    final blob = await codec.encodeAndSign(
      noteRows: rows,
      payloadKeyBytes: payloadKeyBytes,
      signingKeyMaterial: signingKeyMaterial,
    );

    // Flip a bit well past the 64-byte signature prefix, inside the sealed
    // box itself.
    final bytes = base64Decode(blob);
    bytes[bytes.length - 1] ^= 0xff;
    final tamperedBlob = base64Encode(bytes);

    expect(
      () => codec.verifyAndDecode(
        dataBlobBase64: tamperedBlob,
        payloadKeyBytes: payloadKeyBytes,
        trustedPublicKeyBytes: signingKeyMaterial.publicKeyBytes,
      ),
      throwsA(isA<SnapshotIntegrityException>()),
    );
  });

  test('rejects a blob decrypted with the wrong payload key', () async {
    final payloadKeyBytes = fixedPayloadKey();
    final wrongPayloadKeyBytes = Uint8List.fromList(List.generate(32, (i) => 255 - i));
    final signingKeyMaterial = await signing.generateKeyPair();
    final rows = [buildRow('note-1')];

    final blob = await codec.encodeAndSign(
      noteRows: rows,
      payloadKeyBytes: payloadKeyBytes,
      signingKeyMaterial: signingKeyMaterial,
    );

    // The signature still checks out (it signs the still-encrypted sealed
    // box), but AES-GCM decryption with the wrong key must fail.
    expect(
      () => codec.verifyAndDecode(
        dataBlobBase64: blob,
        payloadKeyBytes: wrongPayloadKeyBytes,
        trustedPublicKeyBytes: signingKeyMaterial.publicKeyBytes,
      ),
      throwsException,
    );
  });
}
