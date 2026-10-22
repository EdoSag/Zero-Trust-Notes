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
  Future<List<RemoteItem>> fetch(String app, Set<String> itemIds) async => [
    for (final id in itemIds) ?rows['$app/$id'],
  ];

  @override
  Future<Set<String>> pushAll(String app, List<RemoteItem> items) async {
    final accepted = <String>{};
    for (final item in items) {
      final existing = rows['$app/${item.itemId}'];
      if (existing != null && item.updatedAt.isBefore(existing.updatedAt)) continue;
      final stored = RemoteItem(
        itemId: item.itemId,
        updatedAt: item.updatedAt,
        deviceId: item.deviceId,
        dataBlob: item.dataBlob,
        signature: item.signature,
        deleted: item.deleted,
        syncedAt: DateTime.now().toUtc().add(Duration(microseconds: ++_tick)),
      );
      rows['$app/${item.itemId}'] = stored;
      accepted.add(item.itemId);
      for (final l in List.of(_listeners)) {
        l(stored);
      }
    }
    return accepted;
  }

  @override
  Future<void> Function() subscribe(String app, void Function(RemoteItem) onChange) {
    _listeners.add(onChange);
    return () async => _listeners.remove(onChange);
  }
}
