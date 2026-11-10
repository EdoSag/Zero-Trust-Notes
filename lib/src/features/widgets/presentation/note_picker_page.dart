import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../../../shared/markdown_snippet.dart';
import '../../notes/application/notes_providers.dart';
import '../../notes/domain/note.dart';
import '../application/home_widget_sync_service.dart';
import '../application/widget_details_controller.dart';

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
          title: const Text('Show note text on the home screen?'),
          content: const Text(
            'This turns on "Show details on the home screen" for every note '
            'widget, including ones you already placed. Their titles and the '
            'start of their text will be stored unencrypted on this phone so '
            'the widgets can show them. You can turn this off in Settings.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep hidden')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Show on all widgets')),
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
      appBar: AppBar(title: const Text('Choose a note to pin')),
      body: notesAsync.when(
        data: (notes) {
          if (notes.isEmpty) {
            return const Center(child: Text('No notes yet. Create one first.'));
          }
          return ListView.builder(
            itemCount: notes.length,
            itemBuilder: (context, index) {
              final note = notes[index];
              final title = note.title.isEmpty ? '(untitled)' : note.title;
              return ListTile(
                title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  note.locked ? 'Locked note' : stripMarkdownForSnippet(note.body),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => _pin(context, ref, note),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Failed to load notes: $error')),
      ),
    );
  }
}
