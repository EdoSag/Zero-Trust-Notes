import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../notes/application/notes_providers.dart';
import '../tags/application/tags_controller.dart';
import 'keep_importer.dart';
import 'keep_takeout_parser.dart';

/// Picks files for the Keep import. Overridable in tests.
typedef KeepFilePicker = Future<Map<String, List<int>>> Function();

final keepFilePickerProvider = Provider<KeepFilePicker>((ref) => () async {
  final picked = await FilePicker.pickFiles(dialogTitle: 'Choose your Google Takeout file');
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
      title: const Text('Import from Google Keep'),
      content: const SingleChildScrollView(
        child: Text(
          '1. Go to takeout.google.com and choose only "Keep".\n'
          '2. Download the export to this phone.\n'
          '3. Pick the .zip file here (or the .json files from its Keep folder).\n\n'
          'The file is read on this phone and your notes are encrypted before '
          'they sync. Labels become tags; colours, pins, archive and '
          'checklists come along. Notes already imported are skipped. '
          'Images and recordings aren\'t imported yet.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Choose file'),
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
    if (context.mounted) _snack(context, 'Couldn\'t open that file.');
    return;
  }
  if (files.isEmpty || !context.mounted) {
    if (context.mounted) _snack(context, 'No .zip or .json file was chosen.');
    return;
  }

  final notes = ref.read(notesRepositoryProvider);
  final tags = ref.read(tagsRepositoryProvider);
  if (notes == null || tags == null) return;

  final keepNotes = const KeepTakeoutParser().parseFiles(files);
  if (keepNotes.isEmpty) {
    _snack(context, 'No Google Keep notes were found in that file.');
    return;
  }

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Expanded(child: Text('Importing your notes…')),
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
    _snack(context, 'The import stopped part-way ($failure). Run it again to finish; '
        'notes already imported are skipped.');
    return;
  }
  final r = result;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Imported ${r.imported} ${r.imported == 1 ? 'note' : 'notes'}'),
      content: Text([
        if (r.skippedDuplicates > 0)
          '${r.skippedDuplicates} already in Notes, skipped.',
        if (r.skippedTrashed > 0)
          '${r.skippedTrashed} from Keep\'s trash, skipped.',
        if (r.attachmentsNotImported > 0)
          '${r.attachmentsNotImported} images or recordings weren\'t imported.',
        if (r.skippedDuplicates == 0 && r.skippedTrashed == 0 && r.attachmentsNotImported == 0)
          'Everything came across.',
      ].join('\n')),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

void _snack(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
