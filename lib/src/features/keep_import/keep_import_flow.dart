import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../notes/application/notes_providers.dart';
import '../tags/application/tags_controller.dart';
import 'keep_importer.dart';
import 'keep_takeout_parser.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';

/// Picks files for the Keep import. Overridable in tests.
typedef KeepFilePicker = Future<Map<String, List<int>>> Function();

final keepFilePickerProvider = Provider<KeepFilePicker>((ref) => () async {
  final picked = await FilePicker.pickFiles(dialogTitle: currentL10n.keepChooseFile);
  return {
    for (final file in picked)
      if (file.name.toLowerCase().endsWith('.zip') || file.name.toLowerCase().endsWith('.json'))
        file.name: await file.readAsBytes(),
  };
});

/// Explains how to get a Takeout file, lets the user pick it, and imports.
Future<void> showKeepImportFlow(BuildContext context, WidgetRef ref) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(context.l10n.importFromKeep),
      content: SingleChildScrollView(
        child: Text(
          context.l10n.keepExplain,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(context.l10n.chooseFile),
        ),
      ],
    ),
  );
  if (go != true || !context.mounted) return;

  final Map<String, List<int>> files;
  try {
    // The picker is system UI: don't let auto-lock fire behind it.
    files = await ref
        .read(vaultControllerProvider.notifier)
        .whileShowingSystemUi(ref.read(keepFilePickerProvider));
  } on Object {
    if (context.mounted) _snack(context, context.l10n.cantOpenFile);
    return;
  }
  if (files.isEmpty || !context.mounted) {
    if (context.mounted) _snack(context, context.l10n.noFileChosen);
    return;
  }

  final notes = ref.read(notesRepositoryProvider);
  final tags = ref.read(tagsRepositoryProvider);
  if (notes == null || tags == null) return;

  final keepNotes = const KeepTakeoutParser().parseFiles(files);
  if (keepNotes.isEmpty) {
    _snack(context, context.l10n.keepNoneFound);
    return;
  }

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Expanded(child: Text(context.l10n.importingNotes)),
        ],
      ),
    ),
  );
  KeepImportResult? result;
  Object? failure;
  try {
    result = await KeepImporter(notes: notes, tags: tags).run(keepNotes);
  } on Object catch (e) {
    failure = e;
  }
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();

  if (result == null) {
    _snack(context, context.l10n.keepStopped('$failure'));
    return;
  }
  final r = result;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(context.l10n.keepImportedTitle(r.imported)),
      content: Text([
        if (r.skippedDuplicates > 0)
          context.l10n.keepSkippedDup(r.skippedDuplicates),
        if (r.skippedTrashed > 0)
          context.l10n.keepSkippedTrash(r.skippedTrashed),
        if (r.attachmentsNotImported > 0)
          context.l10n.keepAttachmentsSkipped(r.attachmentsNotImported),
        if (r.skippedDuplicates == 0 && r.skippedTrashed == 0 && r.attachmentsNotImported == 0)
          context.l10n.keepEverything,
      ].join('\n')),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(context.l10n.done),
        ),
      ],
    ),
  );
}

void _snack(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
