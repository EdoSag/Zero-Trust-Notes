import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/auth_providers.dart';
import '../../notes/application/notes_session.dart';
import '../legacy_notes_importer.dart';
import '../legacy_snapshot_codec.dart';

/// Overridable so tests can supply fake sources.
final legacySourcesProvider = Provider<List<LegacyNotesSource> Function(String userId)>(
  (ref) =>
      (userId) => [LocalFileLegacySource(userId), CloudSnapshotLegacySource(userId)],
);

final legacyImporterProvider = Provider<LegacyNotesImporter?>((ref) {
  final session = ref.watch(notesSessionProvider).value;
  final userId = ref.watch(currentUserProvider)?.id;
  if (session == null || userId == null) return null;
  return LegacyNotesImporter(
    sources: ref.watch(legacySourcesProvider)(userId),
    vault: session.vault,
    engine: session.engine,
  );
});

/// Whether there are pre-update notes waiting to be imported.
final legacyImportPendingProvider = FutureProvider<bool>((ref) async {
  final importer = ref.watch(legacyImporterProvider);
  return importer != null && await importer.pendingSource() != null;
});

/// Asks for the old vault passphrase and imports. Returns the number of
/// notes imported, or null when cancelled.
Future<int?> showLegacyImportDialog(BuildContext context) =>
    showDialog<int>(context: context, builder: (_) => const _LegacyImportDialog());

class LegacyImportBanner extends ConsumerStatefulWidget {
  const LegacyImportBanner({super.key});

  @override
  ConsumerState<LegacyImportBanner> createState() => _LegacyImportBannerState();
}

class _LegacyImportBannerState extends ConsumerState<LegacyImportBanner> {
  bool _hidden = false;

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(legacyImportPendingProvider).value ?? false;
    if (!pending || _hidden) return const SizedBox.shrink();
    return MaterialBanner(
      leading: const Icon(Icons.move_down_outlined),
      content: const Text(
        'Notes now uses your Zero-Trust account. Bring over the notes from your old vault?',
      ),
      actions: [
        TextButton(onPressed: () => setState(() => _hidden = true), child: const Text('Later')),
        FilledButton(
          onPressed: () async {
            final count = await showLegacyImportDialog(context);
            if (count == null || !context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Imported $count ${count == 1 ? 'note' : 'notes'}.')),
            );
          },
          child: const Text('Import'),
        ),
      ],
    );
  }
}

class _LegacyImportDialog extends ConsumerStatefulWidget {
  const _LegacyImportDialog();

  @override
  ConsumerState<_LegacyImportDialog> createState() => _LegacyImportDialogState();
}

class _LegacyImportDialogState extends ConsumerState<_LegacyImportDialog> {
  final _passphrase = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _passphrase.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final importer = ref.read(legacyImporterProvider);
    if (importer == null || _passphrase.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final count = await importer.run(_passphrase.text);
      ref.invalidate(legacyImportPendingProvider);
      if (count > 0) ref.read(notesChangedProvider.notifier).bump();
      if (mounted) Navigator.pop(context, count);
    } on WrongLegacyPassphrase {
      if (mounted) setState(() => _error = 'That passphrase doesn\'t open your old notes.');
    } on SnapshotIntegrityException {
      if (mounted) {
        setState(
          () =>
              _error = 'Your old cloud backup failed its integrity check, so it wasn\'t imported.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Couldn\'t import. Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import old notes'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter the vault passphrase you used before this update. It\'s only needed once.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passphrase,
            decoration: InputDecoration(labelText: 'Old vault passphrase', errorText: _error),
            obscureText: true,
            autofocus: true,
            onSubmitted: (_) => _import(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _busy ? null : _import, child: const Text('Import')),
      ],
    );
  }
}
