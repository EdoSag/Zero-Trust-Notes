import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../../../shared/markdown_snippet.dart';
import '../../notes/application/notes_providers.dart';
import '../../notes/domain/note.dart';
import '../application/home_widget_sync_service.dart';

/// Reached only once the vault is confirmed unlocked (see `AppGate`), in
/// response to the OS
/// launching the app to configure a newly-placed Single Note widget. Lets
/// the user pick which note that widget instance pins to its home screen.
class NotePickerPage extends ConsumerWidget {
  const NotePickerPage({super.key, required this.appWidgetId});

  final String appWidgetId;

  Future<void> _pin(BuildContext context, Note note) async {
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
                  stripMarkdownForSnippet(note.body),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => _pin(context, note),
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
