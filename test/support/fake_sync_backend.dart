import 'package:zero_trust_core/zero_trust_core.dart';

/// In-memory `vault_items`, with the server's stale-write guard and
/// `synced_at` stamping.
class FakeSyncBackend implements SyncBackend {
  final Map<String, RemoteItem> rows = {};
  final List<void Function(RemoteItem)> _listeners = [];
  int _tick = 0;

  @override
  Future<List<RemoteItem>> pull(String app, {DateTime? since}) async =>
      rows.entries
          .where((e) => e.key.startsWith('$app/'))
          .map((e) => e.value)
          .where((r) => since == null || r.syncedAt!.isAfter(since))
          .toList()
        ..sort((a, b) => a.syncedAt!.compareTo(b.syncedAt!));

  @override
  Future<bool> push(String app, RemoteItem item) async {
    final existing = rows['$app/${item.itemId}'];
    if (existing != null && item.updatedAt.isBefore(existing.updatedAt)) return false;
    final stored = RemoteItem(
      itemId: item.itemId,
      updatedAt: item.updatedAt,
      deviceId: item.deviceId,
      dataBlob: item.dataBlob,
      signature: item.signature,
      deleted: item.deleted,
      syncedAt: DateTime.utc(2026, 1, 1).add(Duration(seconds: ++_tick)),
    );
    rows['$app/${item.itemId}'] = stored;
    for (final l in List.of(_listeners)) {
      l(stored);
    }
    return true;
  }

  @override
  Future<void> Function() subscribe(String app, void Function(RemoteItem) onChange) {
    _listeners.add(onChange);
    return () async => _listeners.remove(onChange);
  }
}
