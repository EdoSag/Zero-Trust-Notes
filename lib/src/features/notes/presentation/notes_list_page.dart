import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../../../shared/markdown_snippet.dart';
import '../../../shared/theme/app_spacing.dart';
import '../../../shared/widgets/accessible_touch_target.dart';
import '../../legacy_import/presentation/legacy_import.dart';
import '../../notebooks/application/notebooks_controller.dart';
import '../../settings/notes_settings_page.dart';
import '../../sync/application/conflict_copies.dart';
import '../../sync/presentation/sync_status_badge.dart';
import '../application/notes_providers.dart';
import '../domain/note.dart';
import 'note_editor_page.dart';

enum _SortOption {
  updatedDesc('Last edited (newest)'),
  updatedAsc('Last edited (oldest)'),
  createdDesc('Date created (newest)'),
  createdAsc('Date created (oldest)'),
  titleAsc('Title (A-Z)');

  const _SortOption(this.label);
  final String label;
}

/// Sentinel notebook-filter values distinct from any real notebook id.
const _allNotebooksFilter = '__all__';
const _unfiledNotebooksFilter = '__unfiled__';

class NotesListPage extends ConsumerStatefulWidget {
  const NotesListPage({super.key});

  @override
  ConsumerState<NotesListPage> createState() => _NotesListPageState();
}

class _NotesListPageState extends ConsumerState<NotesListPage> {
  final _searchController = TextEditingController();
  bool _searchActive = false;
  String _query = '';
  _SortOption _sort = _SortOption.updatedDesc;
  String _notebookFilter = _allNotebooksFilter;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() => _query = _searchController.text));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Note> _visibleNotes(List<Note> notes) {
    // A notebook deleted on another device (or never carried over from the
    // earlier store) leaves notes pointing at nothing: those count as unfiled.
    final notebookIds = {
      for (final notebook in ref.watch(notebooksListProvider).value ?? const []) notebook.id,
    };
    var result = notes.where((note) {
      if (_notebookFilter == _unfiledNotebooksFilter) {
        return note.notebookId == null || !notebookIds.contains(note.notebookId);
      }
      if (_notebookFilter != _allNotebooksFilter) return note.notebookId == _notebookFilter;
      return true;
    });

    final query = _query.trim().toLowerCase();
    if (query.isNotEmpty) {
      result = result.where(
        (note) => note.title.toLowerCase().contains(query) || note.body.toLowerCase().contains(query),
      );
    }

    final list = result.toList();
    list.sort((a, b) => switch (_sort) {
          _SortOption.updatedDesc => b.updatedAt.compareTo(a.updatedAt),
          _SortOption.updatedAsc => a.updatedAt.compareTo(b.updatedAt),
          _SortOption.createdDesc => b.createdAt.compareTo(a.createdAt),
          _SortOption.createdAsc => a.createdAt.compareTo(b.createdAt),
          _SortOption.titleAsc => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        });
    return list;
  }

  Future<void> _deleteWithUndo(Note note) async {
    final repository = ref.read(notesRepositoryProvider);
    if (repository == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete note?'),
        content: Text('"${note.title.isEmpty ? '(untitled)' : note.title}" will be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await repository.deleteNote(note.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Note deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => ref.read(notesRepositoryProvider)?.updateNote(note),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(notesListProvider);
    ref.watch(conflictCopiesProvider);

    ref.listen(ztSyncControllerProvider, (previous, next) {
      // Once per failure streak; the controller keeps retrying on its own.
      if (next.error != null && previous?.error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Couldn\'t sync. Your notes are saved on this device and will sync later.'),
          ),
        );
      }
    });

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            ref.read(ztSyncControllerProvider.notifier).syncNow(),
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
            ref.read(ztSyncControllerProvider.notifier).syncNow(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: _searchActive
                ? Semantics(
                    textField: true,
                    label: 'Search notes',
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Search notes…',
                        border: InputBorder.none,
                      ),
                    ),
                  )
                : Semantics(
                    header: true,
                    child: const Text('Notes'),
                  ),
            actions: [
              AccessibleIconButton(
                label: _searchActive ? 'Close search' : 'Search notes',
                icon: _searchActive ? Icons.close : Icons.search,
                onPressed: () => setState(() {
                  _searchActive = !_searchActive;
                  if (!_searchActive) _searchController.clear();
                }),
              ),
              PopupMenuButton<_SortOption>(
                tooltip: 'Sort notes',
                icon: const Icon(Icons.sort),
                initialValue: _sort,
                onSelected: (value) => setState(() => _sort = value),
                itemBuilder: (context) => [
                  for (final option in _SortOption.values)
                    PopupMenuItem(value: option, child: Text(option.label)),
                ],
              ),
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
              _NotebookFilterBar(
                selected: _notebookFilter,
                onChanged: (value) => setState(() => _notebookFilter = value),
              ),
              Expanded(
                child: notesAsync.when(
                  data: (notes) => _NotesList(
                    notes: _visibleNotes(notes),
                    hasAnyNotes: notes.isNotEmpty,
                    isFiltered: _query.trim().isNotEmpty || _notebookFilter != _allNotebooksFilter,
                    onDelete: _deleteWithUndo,
                  ),
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

class _NotebookFilterBar extends ConsumerWidget {
  const _NotebookFilterBar({required this.selected, required this.onChanged});

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notebooksAsync = ref.watch(notebooksListProvider);
    return notebooksAsync.maybeWhen(
      data: (notebooks) {
        if (notebooks.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xs),
                child: ChoiceChip(
                  label: const Text('All'),
                  selected: selected == _allNotebooksFilter,
                  onSelected: (_) => onChanged(_allNotebooksFilter),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xs),
                child: ChoiceChip(
                  label: const Text('Unfiled'),
                  selected: selected == _unfiledNotebooksFilter,
                  onSelected: (_) => onChanged(_unfiledNotebooksFilter),
                ),
              ),
              for (final notebook in notebooks)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xs),
                  child: ChoiceChip(
                    label: Text(notebook.name),
                    selected: selected == notebook.id,
                    onSelected: (_) => onChanged(notebook.id),
                  ),
                ),
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _NotesList extends StatelessWidget {
  const _NotesList({
    required this.notes,
    required this.hasAnyNotes,
    required this.isFiltered,
    required this.onDelete,
  });

  final List<Note> notes;
  final bool hasAnyNotes;
  final bool isFiltered;
  final ValueChanged<Note> onDelete;

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isFiltered ? Icons.search_off : Icons.note_add_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                isFiltered
                    ? 'No notes match your search or filter.'
                    : (hasAnyNotes ? 'No notes here yet.' : 'No notes yet. Tap + to create one.'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: notes.length,
      itemBuilder: (context, index) {
        final note = notes[index];
        final title = note.title.isEmpty ? '(untitled)' : note.title;
        final snippet = stripMarkdownForSnippet(note.body);
        return Dismissible(
          key: ValueKey(note.id),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Theme.of(context).colorScheme.errorContainer,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.onErrorContainer),
          ),
          confirmDismiss: (_) async {
            onDelete(note);
            return false;
          },
          child: Semantics(
            label: '$title. $snippet',
            button: true,
            hint: 'Opens note editor',
            excludeSemantics: true,
            child: SizedBox(
              height: 56,
              child: ListTile(
                title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(snippet, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => NoteEditorPage(note: note)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
