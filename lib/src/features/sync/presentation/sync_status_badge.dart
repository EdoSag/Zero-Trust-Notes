import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/sync_controller.dart';

/// Live sync status, announced to screen readers as it changes. Tapping it
/// syncs now.
class SyncStatusBadge extends ConsumerWidget {
  const SyncStatusBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(syncControllerProvider);
    final (label, icon, color) = switch (syncState) {
      SyncIdle() => ('Synced', Icons.cloud_done_outlined, null),
      SyncSyncing() => ('Syncing', Icons.sync, null),
      SyncOffline() => ('Offline', Icons.cloud_off_outlined, Colors.grey),
      SyncError() => ('Not synced', Icons.error_outline, Theme.of(context).colorScheme.error),
    };

    return Semantics(
      liveRegion: true,
      label: 'Sync status: $label',
      button: true,
      hint: 'Sync now',
      child: ActionChip(
        avatar: Icon(icon, size: 18, color: color),
        label: Text(label),
        onPressed: () => ref.read(syncControllerProvider.notifier).syncNow(),
      ),
    );
  }
}
