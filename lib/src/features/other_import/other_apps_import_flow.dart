import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';

import '../notebooks/application/notebooks_controller.dart';
import '../notes/application/notes_providers.dart';
import '../tags/application/tags_controller.dart';
import 'other_apps_importer.dart';
import 'other_apps_parser.dart';

/// Picks the export files to import. Overridable in tests.
typedef OtherAppsFilePicker = Future<Map<String, List<int>>> Function();

final otherAppsFilePickerProvider = Provider<OtherAppsFilePicker>(
  (ref) => () async {
    final picked = await FilePicker.pickFiles(dialogTitle: currentL10n.chooseFile);
    return {for (final file in picked) file.name: await file.readAsBytes()};
  },
);

/// Reads the chosen files off the screen thread, so a big export doesn't
/// freeze Notes while it is read.
final otherAppsParserProvider = Provider<Future<ImportBatch> Function(Map<String, List<int>>)>(
  (ref) =>
      (files) => compute(parseOtherAppsFiles, files),
);

/// Explains where to get an export from Evernote, Standard Notes, Apple
/// Notes or a Markdown app, lets the user pick it, and imports (N-1).
Future<void> showOtherAppsImportFlow(BuildContext context, WidgetRef ref) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(context.l10n.importFromOtherApps),
      content: SingleChildScrollView(child: Text(context.l10n.otherAppsExplain)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          key: const Key('other_import_choose'),
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
        .whileShowingSystemUi(ref.read(otherAppsFilePickerProvider));
  } on Object {
    if (context.mounted) _snack(context, context.l10n.cantOpenFile);
    return;
  }
  if (!context.mounted) return;
  if (files.isEmpty) {
    _snack(context, context.l10n.noFileChosen);
    return;
  }

  final notes = ref.read(notesRepositoryProvider);
  final tags = ref.read(tagsRepositoryProvider);
  if (notes == null || tags == null) return;

  final progress = ValueNotifier<(int, int)?>(null);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: ValueListenableBuilder<(int, int)?>(
          valueListenable: progress,
          builder: (context, value, _) => Row(
            children: [
              CircularProgressIndicator(
                value: value == null || value.$2 == 0 ? null : value.$1 / value.$2,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  value == null
                      ? context.l10n.importingNotes
                      : context.l10n.importProgress(value.$1, value.$2),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  void closeProgress() {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }

  final ImportBatch batch;
  try {
    batch = await ref.read(otherAppsParserProvider)(files);
  } on Object {
    closeProgress();
    if (context.mounted) _snack(context, context.l10n.otherNoneFound);
    return;
  }
  if (!context.mounted) return;
  if (batch.notes.isEmpty) {
    closeProgress();
    _snack(
      context,
      batch.encrypted > 0
          ? context.l10n.otherEncrypted(batch.encrypted)
          : context.l10n.otherNoneFound,
    );
    return;
  }

  OtherAppsImportResult? result;
  Object? failure;
  try {
    result = await OtherAppsImporter(
      notes: notes,
      tags: tags,
      notebooks: ref.read(notebooksRepositoryProvider),
    ).run(batch.notes, onProgress: (done, total) => progress.value = (done, total));
  } on Object catch (e) {
    failure = e;
  }
  closeProgress();
  if (!context.mounted) return;
  if (result == null) {
    _snack(context, context.l10n.keepStopped('$failure'));
    return;
  }
  final r = result;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(context.l10n.keepImportedTitle(r.imported)),
      content: Text(
        [
          if (r.skippedDuplicates > 0) context.l10n.keepSkippedDup(r.skippedDuplicates),
          if (r.skippedTrashed > 0) context.l10n.otherSkippedTrash(r.skippedTrashed),
          if (r.filesNotAdded > 0) context.l10n.otherFilesSkipped(r.filesNotAdded),
          if (batch.encrypted > 0) context.l10n.otherEncrypted(batch.encrypted),
          if (r.skippedDuplicates == 0 &&
              r.skippedTrashed == 0 &&
              r.filesNotAdded == 0 &&
              batch.encrypted == 0)
            context.l10n.keepEverything,
        ].join('\n'),
      ),
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
