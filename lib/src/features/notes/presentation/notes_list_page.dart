import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/accessible_touch_target.dart';
import '../../auth/application/auth_controller.dart';
import '../../export/presentation/export_sheet.dart';
import '../../sync/application/sync_controller.dart';
import '../../sync/presentation/conflict_resolution_dialog.dart';
import '../../sync/presentation/sync_status_badge.dart';
import '../../vault/application/vault_controller.dart';
import '../application/notes_controller.dart';
import '../domain/note.dart';
import 'note_editor_page.dart';

class NotesListPage extends ConsumerWidget {
  const NotesListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(notesListProvider);

    ref.listen(syncControllerProvider, (previous, next) {
      if (next is SyncConflictPending) {
        showConflictResolutionDialog(context, next.conflict);
      } else if (next is SyncError) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.message)));
      }
    });

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            ref.read(syncControllerProvider.notifier).push(),
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
            ref.read(syncControllerProvider.notifier).push(),
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
                label: 'Sync now',
                icon: Icons.sync,
                onPressed: () => ref.read(syncControllerProvider.notifier).push(),
              ),
              AccessibleIconButton(
                label: 'Pull from cloud',
                icon: Icons.cloud_download_outlined,
                onPressed: () => ref.read(syncControllerProvider.notifier).pull(),
              ),
              AccessibleIconButton(
                label: 'Export all notes',
                icon: Icons.ios_share,
                onPressed: () => showExportSheet(context),
              ),
              AccessibleIconButton(
                label: 'Lock vault',
                icon: Icons.lock_outline,
                onPressed: () => ref.read(vaultControllerProvider.notifier).lock(),
              ),
              AccessibleIconButton(
                label: 'Sign out',
                icon: Icons.logout,
                onPressed: () async {
                  await ref.read(vaultControllerProvider.notifier).lock();
                  await ref.read(authControllerProvider.notifier).signOut();
                },
              ),
            ],
          ),
          body: notesAsync.when(
            data: (notes) => _NotesList(notes: notes),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('Failed to load notes: $error')),
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
