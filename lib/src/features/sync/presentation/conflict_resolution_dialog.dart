import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../application/sync_controller.dart';
import '../domain/sync_conflict.dart';

/// Shown when a manual Sync finds the cloud snapshot is newer than what
/// this device last synced — pushing now would silently discard whatever
/// another device already saved, so this makes the choice explicit instead.
Future<void> showConflictResolutionDialog(BuildContext context, SyncConflict conflict) {
  final formatter = DateFormat.yMMMd().add_jm();
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return Consumer(
        builder: (consumerContext, ref, _) {
          void cancel() {
            Navigator.of(dialogContext).pop();
            ref.read(syncControllerProvider.notifier).cancelConflict();
          }

          return CallbackShortcuts(
            bindings: {const SingleActivator(LogicalKeyboardKey.escape): cancel},
            child: Semantics(
              liveRegion: true,
              label: 'Sync conflict detected',
              child: AlertDialog(
                title: Semantics(
                  header: true,
                  child: const Text('Sync conflict'),
                ),
                content: Text(
                  'Another device (${conflict.remoteDeviceId}) saved changes to the '
                  'cloud on ${formatter.format(conflict.remoteUpdatedAt.toLocal())}, '
                  "after this device's last sync. Pushing now would overwrite that.\n\n"
                  'Keep the cloud version (and pull it down), or overwrite the cloud '
                  'with what this device has?',
                ),
                actions: [
                  Semantics(
                    label: 'Cancel',
                    button: true,
                    child: SizedBox(
                      height: 48,
                      child: TextButton(
                        onPressed: cancel,
                        child: const Text('Cancel'),
                      ),
                    ),
                  ),
                  Semantics(
                    label: 'Keep cloud version',
                    button: true,
                    child: SizedBox(
                      height: 48,
                      child: TextButton(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          ref.read(syncControllerProvider.notifier).resolveConflict(
                                keepCloudVersion: true,
                              );
                        },
                        child: const Text('Keep Cloud Version'),
                      ),
                    ),
                  ),
                  Semantics(
                    label: 'Overwrite cloud version',
                    button: true,
                    child: SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          ref.read(syncControllerProvider.notifier).resolveConflict(
                                keepCloudVersion: false,
                              );
                        },
                        child: const Text('Overwrite Cloud Version'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
