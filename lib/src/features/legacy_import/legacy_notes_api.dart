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

/// Read-only access to the pre-core whole-vault snapshot, used once to
/// import notes from a device that no longer has the old local file.
///
/// Talks to `encrypted_notes` — one point-in-time whole-vault snapshot per
/// user, upserted by `user_id` (enforced by a unique index; see the
/// migration). Supabase never sees anything here it could act on: it's an
/// opaque, signed, encrypted blob to this table, exactly as intended by the
/// "Supabase as untrusted blob store" design.
class EncryptedNotesApi {
  EncryptedNotesApi({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<EncryptedNoteSnapshot?> pull(String userId) async {
    final Map<String, dynamic>? row;
    try {
      row = await _client
          .from('encrypted_notes')
          .select('data_blob, device_id, updated_at')
          .eq('user_id', userId)
          .maybeSingle();
    } on PostgrestException catch (e) {
      if (isMissingLegacyTable(e)) return null;
      rethrow;
    }
    if (row == null) return null;

    return EncryptedNoteSnapshot(
      dataBlobBase64: row['data_blob'] as String,
      deviceId: row['device_id'] as String,
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}

/// The pre-core tables were dropped from the database on 2026-11-10. A
/// missing table means there is nothing left to import.
bool isMissingLegacyTable(PostgrestException e) =>
    e.code == 'PGRST205' || e.code == '42P01';
