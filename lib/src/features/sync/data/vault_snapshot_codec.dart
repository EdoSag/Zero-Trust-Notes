import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';

import '../../../core/crypto/payload_cipher_service.dart';
import '../../../core/crypto/signing_service.dart';
import '../../../core/db/local_note_vault.dart';

/// Signature verification failed: the blob was tampered with, corrupted, or
/// signed by a different key than the one we trust for this user.
class SnapshotIntegrityException implements Exception {
  SnapshotIntegrityException(this.message);

  final String message;

  @override
  String toString() => 'SnapshotIntegrityException: $message';
}

/// Turns the local `notes` table into a single signed, encrypted, compressed
/// blob for the manual Sync/Pull flow, and back again.
///
/// Note content itself is never decrypted here — `encryptedTitle`/
/// `encryptedBody`/`encryptedAttachments` are already Tier-2 ciphertext
/// (see `PayloadCipherService`) and travel through the snapshot unchanged.
/// This codec's own AES-256-GCM + Ed25519 layer protects the *shape* of the
/// whole vault (which notes exist, timestamps) as one signed envelope, so
/// sync never has plaintext note content in memory at all.
///
/// Wire format of the blob pushed to `encrypted_notes.data_blob` (base64):
/// `Ed25519 signature (64 bytes) || AES-256-GCM sealed box(gzip(json))`.
class VaultSnapshotCodec {
  VaultSnapshotCodec({PayloadCipherService? cipher, SigningService? signing})
      : _cipher = cipher ?? PayloadCipherService(),
        _signing = signing ?? SigningService();

  static const _signatureLengthBytes = 64;

  final PayloadCipherService _cipher;
  final SigningService _signing;

  Future<List<NoteRow>> readAllNoteRows(LocalNoteVault vault) {
    return vault.select(vault.notes).get();
  }

  /// Builds the signed, encrypted, base64 blob to push.
  Future<String> encodeAndSign({
    required List<NoteRow> noteRows,
    required Uint8List payloadKeyBytes,
    required Ed25519KeyMaterial signingKeyMaterial,
  }) async {
    final jsonBytes = utf8.encode(jsonEncode(noteRows.map(_noteRowToJson).toList()));
    final compressed = Uint8List.fromList(GZipEncoder().encode(jsonBytes));
    final sealedBox = await _cipher.encryptBytes(compressed, payloadKeyBytes);
    final signature = await _signing.sign(sealedBox, signingKeyMaterial);

    final combined = Uint8List(signature.length + sealedBox.length)
      ..setRange(0, signature.length, signature)
      ..setRange(signature.length, signature.length + sealedBox.length, sealedBox);
    return base64Encode(combined);
  }

  /// Verifies, decrypts, and decompresses a pulled blob into note rows.
  /// Throws [SnapshotIntegrityException] if the signature doesn't check out
  /// against [trustedPublicKeyBytes] — this is the actual defense against a
  /// tampered or forged row, since RLS only enforces row ownership.
  Future<List<NoteRow>> verifyAndDecode({
    required String dataBlobBase64,
    required Uint8List payloadKeyBytes,
    required Uint8List trustedPublicKeyBytes,
  }) async {
    final combined = base64Decode(dataBlobBase64);
    if (combined.length <= _signatureLengthBytes) {
      throw SnapshotIntegrityException('Snapshot blob is too short to contain a signature.');
    }

    final signature = Uint8List.sublistView(combined, 0, _signatureLengthBytes);
    final sealedBox = Uint8List.sublistView(combined, _signatureLengthBytes);

    final isValid = await _signing.verify(
      sealedBox,
      signatureBytes: signature,
      publicKeyBytes: trustedPublicKeyBytes,
    );
    if (!isValid) {
      throw SnapshotIntegrityException(
        'Snapshot signature does not match the trusted public key — refusing to '
        'apply what may be a tampered or forged snapshot.',
      );
    }

    final compressed = await _cipher.decryptBytes(sealedBox, payloadKeyBytes);
    final jsonBytes = GZipDecoder().decodeBytes(compressed);
    final decoded = jsonDecode(utf8.decode(jsonBytes)) as List<dynamic>;
    return decoded.map((entry) => _noteRowFromJson(entry as Map<String, dynamic>)).toList();
  }

  /// Replaces the local `notes` table's contents with [noteRows] — this is
  /// the "whole-blob last-write-wins" merge: the pulled snapshot becomes the
  /// new local state wholesale, it isn't merged row by row.
  Future<void> applySnapshot(LocalNoteVault vault, List<NoteRow> noteRows) async {
    await vault.transaction(() async {
      await vault.delete(vault.notes).go();
      for (final row in noteRows) {
        await vault.into(vault.notes).insert(row.toCompanion(true));
      }
    });
  }

  Map<String, dynamic> _noteRowToJson(NoteRow row) => {
        'id': row.id,
        'notebookId': row.notebookId,
        'encryptedTitle': base64Encode(row.encryptedTitle),
        'encryptedBody': base64Encode(row.encryptedBody),
        'encryptedAttachments':
            row.encryptedAttachments != null ? base64Encode(row.encryptedAttachments!) : null,
        'createdAt': row.createdAt.toUtc().toIso8601String(),
        'updatedAt': row.updatedAt.toUtc().toIso8601String(),
        'isDeleted': row.isDeleted,
      };

  NoteRow _noteRowFromJson(Map<String, dynamic> json) => NoteRow(
        id: json['id'] as String,
        notebookId: json['notebookId'] as String?,
        encryptedTitle: base64Decode(json['encryptedTitle'] as String),
        encryptedBody: base64Decode(json['encryptedBody'] as String),
        encryptedAttachments: json['encryptedAttachments'] != null
            ? base64Decode(json['encryptedAttachments'] as String)
            : null,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        isDeleted: json['isDeleted'] as bool,
      );
}
