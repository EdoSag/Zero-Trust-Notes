import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';

/// Live sync status, announced to screen readers as it changes. Tapping it
/// syncs now. Settings shows the longer `ZtSyncStatusTile`.
class SyncStatusBadge extends ConsumerWidget {
  const SyncStatusBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(ztSyncControllerProvider);
    final (label, icon, color) = switch (status) {
      SyncStatus(isSyncing: true) => (context.l10n.syncing, Icons.sync, null),
      SyncStatus(error: _?) => (
        context.l10n.notSynced,
        Icons.cloud_off_outlined,
        Theme.of(context).colorScheme.error,
      ),
      SyncStatus(lastSyncedAt: null) => (context.l10n.notSyncedYet, Icons.cloud_queue, null),
      _ => (context.l10n.synced, Icons.cloud_done_outlined, null),
    };

    return Semantics(
      liveRegion: true,
      label: context.l10n.syncStatus(label),
      button: true,
      hint: context.l10n.syncNow,
      child: ActionChip(
        avatar: Icon(icon, size: 18, color: color),
        label: Text(label),
        onPressed: () => ref.read(ztSyncControllerProvider.notifier).syncNow(),
      ),
    );
  }
}
