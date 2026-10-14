import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/accessible_touch_target.dart';
import '../../legacy_import/presentation/legacy_import.dart';
import '../../settings/notes_settings_page.dart';
import '../../sync/application/sync_controller.dart';
import '../../sync/presentation/sync_status_badge.dart';
import '../application/notes_session.dart';
import '../domain/note.dart';
import 'note_editor_page.dart';

class NotesListPage extends ConsumerWidget {
  const NotesListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(notesListProvider);

    ref.listen(syncControllerProvider, (previous, next) {
      if (next is SyncError) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.message)));
      }
    });

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            ref.read(syncControllerProvider.notifier).syncNow(),
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
            ref.read(syncControllerProvider.notifier).syncNow(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: Semantics(
              header: true,
              child: const Text('Notes'),
            ),
            actions: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: SyncStatusBadge(),
              ),
              AccessibleIconButton(
                label: 'Settings',
                icon: Icons.settings_outlined,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const NotesSettingsPage()),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              const LegacyImportBanner(),
              Expanded(
                child: notesAsync.when(
                  data: (notes) => _NotesList(notes: notes),
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(child: Text('Failed to load notes: $error')),
                ),
              ),
            ],
          ),
          floatingActionButton: Semantics(
            label: 'Create new note',
            button: true,
            child: SizedBox(
              height: 48,
              width: 48,
              child: FloatingActionButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NoteEditorPage()),
                ),
                child: const Icon(Icons.add),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotesList extends StatelessWidget {
  const _NotesList({required this.notes});

  final List<Note> notes;

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) {
      return const Center(child: Text('No notes yet. Tap + to create one.'));
    }
    return ListView.builder(
      itemCount: notes.length,
      itemBuilder: (context, index) {
        final note = notes[index];
        final title = note.title.isEmpty ? '(untitled)' : note.title;
        return Semantics(
          label: '$title. ${note.body}',
          button: true,
          hint: 'Opens note editor',
          excludeSemantics: true,
          child: SizedBox(
            height: 56,
            child: ListTile(
              title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(note.body, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => NoteEditorPage(note: note)),
              ),
            ),
          ),
        );
      },
    );
  }
}
