import 'package:supabase_flutter/supabase_flutter.dart';

class EncryptedNoteSnapshot {
  const EncryptedNoteSnapshot({
    required this.dataBlobBase64,
    required this.deviceId,
    required this.updatedAt,
  });

  final String dataBlobBase64;
  final String deviceId;
  final DateTime updatedAt;
}

/// Talks to `encrypted_notes` — one point-in-time whole-vault snapshot per
/// user, upserted by `user_id` (enforced by a unique index; see the
/// migration). Supabase never sees anything here it could act on: it's an
/// opaque, signed, encrypted blob to this table, exactly as intended by the
/// "Supabase as untrusted blob store" design.
class EncryptedNotesApi {
  EncryptedNotesApi({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<EncryptedNoteSnapshot?> pull(String userId) async {
    final row = await _client
        .from('encrypted_notes')
        .select('data_blob, device_id, updated_at')
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) return null;

    return EncryptedNoteSnapshot(
      dataBlobBase64: row['data_blob'] as String,
      deviceId: row['device_id'] as String,
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  /// Returns the timestamp that was actually written, so the caller can
  /// cache it locally as `last_sync_timestamp` without a second round trip.
  Future<DateTime> push({
    required String userId,
    required String deviceId,
    required String dataBlobBase64,
  }) async {
    final now = DateTime.now().toUtc();
    await _client.from('encrypted_notes').upsert(
      {
        'user_id': userId,
        'device_id': deviceId,
        'data_blob': dataBlobBase64,
        'updated_at': now.toIso8601String(),
      },
      onConflict: 'user_id',
    );
    return now;
  }
}
