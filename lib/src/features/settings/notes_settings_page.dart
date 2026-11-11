import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../export/presentation/export_sheet.dart';
import '../keep_import/keep_import_flow.dart';
import '../legacy_import/presentation/legacy_import.dart';
import '../widgets/application/home_widget_sync_service.dart';
import '../widgets/application/widget_details_controller.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';

/// The shared Zero-Trust settings screen, plus Notes' own backup rows.
class NotesSettingsPage extends ConsumerWidget {
  const NotesSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final importPending = ref.watch(legacyImportPendingProvider).value ?? false;
    final widgetDetails = ref.watch(widgetDetailsProvider).value ?? false;
    return ZtSettingsPage(
      onSignedOut: () =>
          Navigator.of(context).popUntil((route) => route.isFirst),
      showSyncStatus: true,
      onOpenUrl: (url) => launchUrl(url, mode: LaunchMode.externalApplication),
      appSection: [
        if (HomeWidgetSyncService.isSupported)
          SwitchListTile(
            secondary: const Icon(Icons.widgets_outlined),
            title: Text(context.l10n.widgetDetails),
            subtitle: Text(
              context.l10n.widgetDetailsBody,
            ),
            value: widgetDetails,
            onChanged: (v) => ref.read(widgetDetailsProvider.notifier).set(v),
          ),
      ],
      backupSection: [
        ListTile(
          leading: const Icon(Icons.ios_share),
          title: Text(context.l10n.exportAll),
          subtitle: Text(context.l10n.exportFormats),
          onTap: () => showExportSheet(context),
        ),
        ListTile(
          leading: const Icon(Icons.download_outlined),
          title: Text(context.l10n.importFromKeep),
          subtitle: Text(context.l10n.keepSubtitle),
          onTap: () => showKeepImportFlow(context, ref),
        ),
        if (importPending)
          ListTile(
            leading: const Icon(Icons.move_down_outlined),
            title: Text(context.l10n.importOldVault),
            subtitle: Text(
              context.l10n.importOldVaultSub,
            ),
            onTap: () async {
              final count = await showLegacyImportDialog(context);
              if (count == null || !context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    context.l10n.importedNotes(count),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
