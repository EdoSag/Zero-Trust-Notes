import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../export/presentation/export_sheet.dart';
import '../legacy_import/presentation/legacy_import.dart';

/// The shared Zero-Trust settings screen, plus Notes' own backup rows.
class NotesSettingsPage extends ConsumerWidget {
  const NotesSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final importPending = ref.watch(legacyImportPendingProvider).value ?? false;
    return ZtSettingsPage(
      onSignedOut: () => Navigator.of(context).popUntil((route) => route.isFirst),
      showSyncStatus: true,
      backupSection: [
        ListTile(
          leading: const Icon(Icons.ios_share),
          title: const Text('Export all notes'),
          subtitle: const Text('Markdown, JSON or PDF'),
          onTap: () => showExportSheet(context),
        ),
        if (importPending)
          ListTile(
            leading: const Icon(Icons.move_down_outlined),
            title: const Text('Import notes from your old vault'),
            subtitle: const Text('Needs the vault passphrase you used before this update'),
            onTap: () async {
              final count = await showLegacyImportDialog(context);
              if (count == null || !context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Imported $count ${count == 1 ? 'note' : 'notes'}.')),
              );
            },
          ),
      ],
    );
  }
}
