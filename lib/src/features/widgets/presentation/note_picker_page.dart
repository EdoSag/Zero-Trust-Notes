import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../../../shared/markdown_snippet.dart';
import '../../notes/application/notes_providers.dart';
import '../../notes/domain/note.dart';
import '../application/home_widget_sync_service.dart';
import '../application/widget_details_controller.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';

/// Reached only once the vault is confirmed unlocked (see `AppGate`), in
/// response to the OS
/// launching the app to configure a newly-placed Single Note widget. Lets
/// the user pick which note that widget instance pins to its home screen.
class NotePickerPage extends ConsumerWidget {
  const NotePickerPage({super.key, required this.appWidgetId});

  final String appWidgetId;

  Future<void> _pin(BuildContext context, WidgetRef ref, Note note) async {
    // The widget can only show the note if note text may leave the vault:
    // ask once, here, rather than leave a widget that only shows a lock.
    if (!await const HomeWidgetSyncService().detailsAllowed() && context.mounted) {
      final show = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.showTextQ),
          content: Text(
            context.l10n.showTextBody,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.l10n.keepHidden)),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.l10n.showOnAll)),
          ],
        ),
      );
      if (show == true) {
        await ref.read(widgetDetailsProvider.notifier).set(true);
      }
    }
    await const HomeWidgetSyncService().pinNote(appWidgetId: appWidgetId, note: note);
    await HomeWidget.finishHomeWidgetConfigure();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(notesListProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.chooseNoteToPin)),
      body: notesAsync.when(
        data: (notes) {
          if (notes.isEmpty) {
            return Center(child: Text(context.l10n.noNotesCreateFirst));
          }
          return ListView.builder(
            itemCount: notes.length,
            itemBuilder: (context, index) {
              final note = notes[index];
              final title = note.title.isEmpty ? '(untitled)' : note.title;
              return ListTile(
                title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  note.locked ? context.l10n.lockedNote : stripMarkdownForSnippet(note.body),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => _pin(context, ref, note),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(context.l10n.failedNotes('$error'))),
      ),
    );
  }
}
