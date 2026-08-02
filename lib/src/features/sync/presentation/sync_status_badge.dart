import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/sync_controller.dart';

/// Live status indicator for the current sync phase (Idle, Encrypting,
/// Syncing, Conflict, Offline), announced to screen readers as it changes.
class SyncStatusBadge extends ConsumerWidget {
  const SyncStatusBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(syncControllerProvider);
    final (label, icon, color) = switch (syncState) {
      SyncIdle() => ('Idle', Icons.cloud_done_outlined, null),
      SyncEncrypting() => ('Encrypting', Icons.lock_outline, null),
      SyncSyncing() => ('Syncing', Icons.sync, null),
      SyncOffline() => ('Offline', Icons.cloud_off_outlined, Colors.grey),
      SyncConflictPending() => ('Conflict', Icons.warning_amber_outlined, Colors.orange),
      SyncError() => ('Error', Icons.error_outline, Theme.of(context).colorScheme.error),
    };

    return Semantics(
      liveRegion: true,
      label: 'Sync status: $label',
      child: Chip(
        avatar: Icon(icon, size: 18, color: color),
        label: Text(label),
      ),
    );
  }
}
