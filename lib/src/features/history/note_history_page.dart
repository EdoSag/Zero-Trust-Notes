import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';

import '../../shared/markdown_snippet.dart';
import '../notes/application/notes_providers.dart';
import '../notes/domain/checklist_item.dart';
import 'note_history.dart';

final _versionsProvider = StreamProvider.autoDispose.family<List<NoteVersion>, String>((
  ref,
  noteId,
) {
  final history = ref.watch(noteHistoryProvider);
  if (history == null) return const Stream.empty();
  return history.watch(noteId);
});

String _when(BuildContext context, DateTime at) {
  final locale = context.l10n.localeName;
  try {
    return DateFormat.yMMMd(locale).add_Hm().format(at.toLocal());
  } on Object {
    return DateFormat.yMMMd().add_Hm().format(at.toLocal());
  }
}

/// Version history (N-2): the earlier texts of note [noteId], newest
/// first. Pops the version to bring back, or null.
class NoteHistoryPage extends ConsumerWidget {
  const NoteHistoryPage({super.key, required this.noteId});

  final String noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final versions = ref.watch(_versionsProvider(noteId));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.versionHistory)),
      body: switch (versions) {
        AsyncData(:final value) when value.isEmpty => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(l10n.noVersionsYet, textAlign: TextAlign.center),
          ),
        ),
        AsyncData(:final value) => ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(l10n.versionHistoryHelp, style: Theme.of(context).textTheme.bodySmall),
            ),
            for (final version in value)
              ListTile(
                key: ValueKey('note_version_${version.id}'),
                leading: const Icon(Icons.history),
                title: Text(_when(context, version.savedAt)),
                subtitle: Text(
                  [
                    if (version.title.trim().isNotEmpty) version.title.trim(),
                    stripMarkdownForSnippet(version.body),
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () async {
                  final restore = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(builder: (_) => _VersionPage(version: version)),
                  );
                  if (restore == true && context.mounted) Navigator.of(context).pop(version);
                },
              ),
          ],
        ),
        AsyncError() => Center(child: Text(l10n.cantLoadVersions)),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _VersionPage extends StatelessWidget {
  const _VersionPage({required this.version});

  final NoteVersion version;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final checklist = version.checklist;
    return Scaffold(
      appBar: AppBar(
        title: Text(_when(context, version.savedAt)),
        actions: [
          TextButton.icon(
            key: const Key('note_version_restore'),
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.restore),
            label: Text(l10n.restoreVersion),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (version.title.trim().isNotEmpty) ...[
            Text(version.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
          ],
          if (checklist != null)
            for (final ChecklistItem item in checklist)
              ListTile(
                dense: true,
                leading: Icon(item.checked ? Icons.check_box : Icons.check_box_outline_blank),
                title: Text(item.text),
              )
          else
            MarkdownBody(data: version.body, selectable: true),
        ],
      ),
    );
  }
}
