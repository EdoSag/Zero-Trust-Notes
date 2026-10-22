import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

/// When another device's newer edit wins over an unsynced local one, keeps
/// the local version as a separate "conflicted copy" note, so nothing a user
/// typed is ever silently lost. Active while something listens to it (the
/// notes list does).
final conflictCopiesProvider = Provider<void>((ref) {
  const uuid = Uuid();
  ref.listen(ztSyncControllerProvider, (_, status) {
    final conflicts = status.conflicts;
    if (conflicts.isEmpty) return;
    // Not inside the status change that is notifying us.
    scheduleMicrotask(() async {
      final sync = ref.read(ztSyncControllerProvider.notifier)..clearConflicts();
      for (final conflict in conflicts) {
        final lost = conflict.lostLocal.json;
        if (lost == null) continue; // a local delete lost; nothing to restore
        final title = (lost['title'] as String?) ?? '';
        await sync.save(uuid.v4(), {
          ...lost,
          'title': title.isEmpty ? 'Conflicted copy' : '$title (conflicted copy)',
        });
      }
    });
  });
});
