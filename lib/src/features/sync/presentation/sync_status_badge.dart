import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

/// Live sync status, announced to screen readers as it changes. Tapping it
/// syncs now. Settings shows the longer `ZtSyncStatusTile`.
class SyncStatusBadge extends ConsumerWidget {
  const SyncStatusBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(ztSyncControllerProvider);
    final (label, icon, color) = switch (status) {
      SyncStatus(isSyncing: true) => ('Syncing', Icons.sync, null),
      SyncStatus(error: _?) => (
        'Not synced',
        Icons.cloud_off_outlined,
        Theme.of(context).colorScheme.error,
      ),
      SyncStatus(lastSyncedAt: null) => ('Not synced yet', Icons.cloud_queue, null),
      _ => ('Synced', Icons.cloud_done_outlined, null),
    };

    return Semantics(
      liveRegion: true,
      label: 'Sync status: $label',
      button: true,
      hint: 'Sync now',
      child: ActionChip(
        avatar: Icon(icon, size: 18, color: color),
        label: Text(label),
        onPressed: () => ref.read(ztSyncControllerProvider.notifier).syncNow(),
      ),
    );
  }
}
