import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../../../shared/theme/app_spacing.dart';
import '../../../shared/widgets/accessible_touch_target.dart';
import '../../keep_import/keep_import_flow.dart';
import '../../legacy_import/presentation/legacy_import.dart';
import '../../notebooks/application/notebooks_controller.dart';
import '../../notebooks/domain/notebook.dart';
import '../../settings/notes_settings_page.dart';
import '../../sync/application/conflict_copies.dart';
import '../../sync/presentation/sync_status_badge.dart';
import '../../tags/application/tags_controller.dart';
import '../../tags/domain/tag.dart';
import '../application/notes_layout.dart';
import '../application/notes_providers.dart';
import '../domain/note.dart';
import '../domain/note_color.dart';
import '../domain/notes_filter.dart';
import 'note_actions.dart';
import 'note_card.dart';
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

class NotesListPage extends ConsumerStatefulWidget {
  const NotesListPage({super.key});

  @override
  ConsumerState<NotesListPage> createState() => _NotesListPageState();
}

class _NotesListPageState extends ConsumerState<NotesListPage> {
  final _searchController = TextEditingController();
  bool _searchActive = false;
  _SortOption _sort = _SortOption.updatedDesc;
  NotesFilter _filter = const NotesFilter();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(
      () => setState(() => _filter = _filter.copyWith(query: _searchController.text)),
    );
    // Notes kept in Trash past 30 days are deleted for good.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(notesRepositoryProvider)?.purgeExpiredTrash().catchError((_) => 0));
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _setView(NotesView view) {
    setState(() {
      _filter = NotesFilter(view: view);
      _searchActive = false;
      _searchController.clear();
    });
  }

  List<Note> _sorted(List<Note> notes) {
    final list = [...notes];
    list.sort(
      (a, b) => switch (_sort) {
        _SortOption.updatedDesc => b.updatedAt.compareTo(a.updatedAt),
        _SortOption.updatedAsc => a.updatedAt.compareTo(b.updatedAt),
        _SortOption.createdDesc => b.createdAt.compareTo(a.createdAt),
        _SortOption.createdAsc => a.createdAt.compareTo(b.createdAt),
        _SortOption.titleAsc => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      },
    );
    return list;
  }

  void _open(Note note) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => NoteEditorPage(note: note)));

  void _create({bool checklist = false}) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => NoteEditorPage(
        startAsChecklist: checklist,
        initialNotebookId: _filter.notebookId,
        initialTagId: _filter.tagId,
        archived: _filter.view == NotesView.archive,
      ),
    ),
  );

  Future<void> _emptyTrash() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Empty Trash?'),
        content: const Text(
          'All notes in Trash will be deleted on every device. This can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Empty Trash'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(notesRepositoryProvider)?.emptyTrash();
  }

  String get _title => switch (_filter.view) {
    NotesView.notes => 'Notes',
    NotesView.reminders => 'Reminders',
    NotesView.archive => 'Archive',
    NotesView.trash => 'Trash',
  };

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(allNotesProvider);
    final tags = ref.watch(tagsListProvider).value ?? const <Tag>[];
    final notebooks = ref.watch(notebooksListProvider).value ?? const <Notebook>[];
    final layout = ref.watch(notesLayoutProvider);
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

    final canCreate = _filter.view == NotesView.notes || _filter.view == NotesView.archive;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            ref.read(ztSyncControllerProvider.notifier).syncNow(),
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
            ref.read(ztSyncControllerProvider.notifier).syncNow(),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            setState(() => _searchActive = true),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          drawer: _NotesDrawer(
            filter: _filter,
            notebooks: notebooks,
            tags: tags,
            onView: (view) {
              Navigator.of(context).pop();
              _setView(view);
            },
            onNotebook: (id) {
              Navigator.of(context).pop();
              setState(() => _filter = NotesFilter(notebookId: id));
            },
            onTag: (id) {
              Navigator.of(context).pop();
              setState(() => _filter = NotesFilter(tagId: id));
            },
            onImportFromKeep: () => showKeepImportFlow(context, ref),
          ),
          appBar: AppBar(
            title: _searchActive
                ? Semantics(
                    textField: true,
                    label: 'Search notes',
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search ${_title.toLowerCase()}…',
                        border: InputBorder.none,
                      ),
                    ),
                  )
                : Semantics(header: true, child: Text(_heading(notebooks, tags))),
            actions: [
              AccessibleIconButton(
                label: _searchActive ? 'Close search' : 'Search notes',
                icon: _searchActive ? Icons.close : Icons.search,
                onPressed: () => setState(() {
                  _searchActive = !_searchActive;
                  if (!_searchActive) {
                    _searchController.clear();
                    _filter = NotesFilter(
                      view: _filter.view,
                      notebookId: _filter.notebookId,
                      tagId: _filter.tagId,
                    );
                  }
                }),
              ),
              AccessibleIconButton(
                label: layout == NotesLayout.grid ? 'Show as list' : 'Show as grid',
                icon: layout == NotesLayout.grid ? Icons.view_agenda_outlined : Icons.grid_view,
                onPressed: () => ref.read(notesLayoutProvider.notifier).toggle(),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: SyncStatusBadge(),
              ),
              PopupMenuButton<Object>(
                tooltip: 'More options',
                onSelected: (value) {
                  if (value is _SortOption) setState(() => _sort = value);
                  if (value == 'empty') _emptyTrash();
                },
                itemBuilder: (context) => [
                  if (_filter.view == NotesView.trash)
                    const PopupMenuItem(value: 'empty', child: Text('Empty Trash')),
                  if (_filter.view == NotesView.notes || _filter.view == NotesView.archive)
                    for (final option in _SortOption.values)
                      CheckedPopupMenuItem(
                        value: option,
                        checked: option == _sort,
                        child: Text(option.label),
                      ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              const LegacyImportBanner(),
              if (_searchActive)
                _SearchFilters(
                  filter: _filter,
                  tags: tags,
                  notebooks: notebooks,
                  onChanged: (filter) => setState(() => _filter = filter),
                )
              else if (_filter.view == NotesView.notes && _filter.tagId == null)
                _NotebookFilterBar(
                  filter: _filter,
                  notebooks: notebooks,
                  onChanged: (filter) => setState(() => _filter = filter),
                ),
              if (_filter.view == NotesView.trash)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    0,
                  ),
                  child: Text(
                    'Notes in Trash are deleted after 30 days.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              Expanded(
                child: notesAsync.when(
                  data: (all) {
                    final visible = _filter.apply(_sorted(all), tags: tags, notebooks: notebooks);
                    final sections = _filter.pinnedFirst(visible);
                    final tagNames = {for (final tag in tags) tag.id: tag.name};
                    return _NotesBody(
                      pinned: sections.pinned,
                      others: sections.others,
                      layout: layout,
                      view: _filter.view,
                      isFiltering: _filter.isFiltering,
                      hasAnyNotes: all.any((note) => !note.isTrashed),
                      tagNames: tagNames,
                      onOpen: _open,
                      onLongPress: (note) => NoteActions(context, ref).showSheet(note),
                      onSwipe: (note) => NoteActions(context, ref).toggleArchive(note),
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(child: Text('Failed to load notes: $error')),
                ),
              ),
            ],
          ),
          floatingActionButton: canCreate
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FloatingActionButton.small(
                      heroTag: 'new_list',
                      tooltip: 'New checklist',
                      onPressed: () => _create(checklist: true),
                      child: const Icon(Icons.checklist),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    FloatingActionButton(
                      heroTag: 'new_note',
                      tooltip: 'Create new note',
                      onPressed: _create,
                      child: const Icon(Icons.add),
                    ),
                  ],
                )
              : null,
        ),
      ),
    );
  }

  String _heading(List<Notebook> notebooks, List<Tag> tags) {
    if (_filter.tagId != null) {
      return tags.where((tag) => tag.id == _filter.tagId).firstOrNull?.name ?? 'Tag';
    }
    return _title;
  }
}

class _NotesDrawer extends ConsumerWidget {
  const _NotesDrawer({
    required this.filter,
    required this.notebooks,
    required this.tags,
    required this.onView,
    required this.onNotebook,
    required this.onTag,
    required this.onImportFromKeep,
  });

  final NotesFilter filter;
  final List<Notebook> notebooks;
  final List<Tag> tags;
  final ValueChanged<NotesView> onView;
  final ValueChanged<String> onNotebook;
  final ValueChanged<String> onTag;

  /// Runs on the notes page, which outlives the drawer: the drawer's own
  /// context is gone as soon as it closes, so a flow started from it would
  /// stop at its first dialog.
  final VoidCallback onImportFromKeep;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plainView = filter.notebookId == null && filter.tagId == null;
    Widget viewTile(NotesView view, IconData icon, String label) => ListTile(
      leading: Icon(icon),
      title: Text(label),
      selected: plainView && filter.view == view,
      onTap: () => onView(view),
    );
    return NavigationDrawer(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 16, 8),
          child: Text('ZT Notes', style: Theme.of(context).textTheme.titleLarge),
        ),
        viewTile(NotesView.notes, Icons.lightbulb_outline, 'Notes'),
        viewTile(NotesView.reminders, Icons.notifications_none, 'Reminders'),
        if (notebooks.isNotEmpty) ...[
          const Divider(),
          const _DrawerHeading('Notebooks'),
          for (final notebook in notebooks)
            ListTile(
              leading: const Icon(Icons.book_outlined),
              title: Text(notebook.name),
              selected: filter.notebookId == notebook.id,
              onTap: () => onNotebook(notebook.id),
            ),
        ],
        if (tags.isNotEmpty) ...[
          const Divider(),
          const _DrawerHeading('Tags'),
          for (final tag in tags)
            ListTile(
              leading: const Icon(Icons.label_outline),
              title: Text(tag.name),
              selected: filter.tagId == tag.id,
              onTap: () => onTag(tag.id),
            ),
        ],
        const Divider(),
        viewTile(NotesView.archive, Icons.archive_outlined, 'Archive'),
        viewTile(NotesView.trash, Icons.delete_outline, 'Trash'),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.download_outlined),
          title: const Text('Import from Google Keep'),
          onTap: () {
            Navigator.of(context).pop();
            onImportFromKeep();
          },
        ),
        ListTile(
          leading: const Icon(Icons.settings_outlined),
          title: const Text('Settings'),
          onTap: () {
            Navigator.of(context).pop();
            Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const NotesSettingsPage()));
          },
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

class _DrawerHeading extends StatelessWidget {
  const _DrawerHeading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(28, 8, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

/// Notebook chips above the main Notes view.
class _NotebookFilterBar extends StatelessWidget {
  const _NotebookFilterBar({required this.filter, required this.notebooks, required this.onChanged});

  final NotesFilter filter;
  final List<Notebook> notebooks;
  final ValueChanged<NotesFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    if (notebooks.isEmpty) return const SizedBox.shrink();
    final all = filter.notebookId == null && !filter.unfiledOnly;
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
              selected: all,
              onSelected: (_) => onChanged(filter.copyWith(notebookId: null, unfiledOnly: false)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: ChoiceChip(
              label: const Text('Unfiled'),
              selected: filter.unfiledOnly,
              onSelected: (_) => onChanged(filter.copyWith(notebookId: null, unfiledOnly: true)),
            ),
          ),
          for (final notebook in notebooks)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: ChoiceChip(
                label: Text(notebook.name),
                selected: filter.notebookId == notebook.id,
                onSelected: (_) =>
                    onChanged(filter.copyWith(notebookId: notebook.id, unfiledOnly: false)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Type, reminder, colour, tag and notebook filters shown while searching.
class _SearchFilters extends StatelessWidget {
  const _SearchFilters({
    required this.filter,
    required this.tags,
    required this.notebooks,
    required this.onChanged,
  });

  final NotesFilter filter;
  final List<Tag> tags;
  final List<Notebook> notebooks;
  final ValueChanged<NotesFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final tagName = tags.where((t) => t.id == filter.tagId).firstOrNull?.name;
    final notebookName = notebooks.where((n) => n.id == filter.notebookId).firstOrNull?.name;
    Widget gap(Widget child) =>
        Padding(padding: const EdgeInsets.only(right: AppSpacing.xs), child: child);

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        children: [
          gap(
            FilterChip(
              avatar: const Icon(Icons.checklist, size: 18),
              label: const Text('Checklists'),
              selected: filter.checklistsOnly,
              onSelected: (on) => onChanged(filter.copyWith(checklistsOnly: on)),
            ),
          ),
          gap(
            FilterChip(
              avatar: const Icon(Icons.alarm, size: 18),
              label: const Text('Reminders'),
              selected: filter.withReminderOnly,
              onSelected: (on) => onChanged(filter.copyWith(withReminderOnly: on)),
            ),
          ),
          gap(
            FilterChip(
              avatar: filter.color == null
                  ? const Icon(Icons.palette_outlined, size: 18)
                  : CircleAvatar(backgroundColor: filter.color!.background(brightness)),
              label: Text(filter.color?.label ?? 'Colour'),
              selected: filter.color != null,
              onSelected: (_) async {
                if (filter.color != null) {
                  onChanged(filter.copyWith(color: null));
                  return;
                }
                final color = await showNoteColorPicker(context, NoteColor.none);
                if (color != null) onChanged(filter.copyWith(color: color));
              },
            ),
          ),
          if (tags.isNotEmpty)
            gap(
              _MenuChip<String>(
                icon: Icons.label_outline,
                label: tagName ?? 'Tag',
                selected: filter.tagId != null,
                options: {for (final tag in tags) tag.id: tag.name},
                onSelected: (id) => onChanged(filter.copyWith(tagId: id)),
              ),
            ),
          if (notebooks.isNotEmpty)
            gap(
              _MenuChip<String>(
                icon: Icons.book_outlined,
                label: notebookName ?? 'Notebook',
                selected: filter.notebookId != null,
                options: {for (final notebook in notebooks) notebook.id: notebook.name},
                onSelected: (id) => onChanged(filter.copyWith(notebookId: id)),
              ),
            ),
          if (filter.isFiltering)
            TextButton(onPressed: () => onChanged(filter.cleared().copyWith(query: filter.query)),
                child: const Text('Clear filters')),
        ],
      ),
    );
  }
}

/// A filter chip that opens a menu; picking the selected value clears it.
class _MenuChip<T> extends StatelessWidget {
  const _MenuChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.options,
    required this.onSelected,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Map<T, String> options;
  final ValueChanged<T?> onSelected;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        if (selected) MenuItemButton(onPressed: () => onSelected(null), child: const Text('Any')),
        for (final MapEntry(:key, :value) in options.entries)
          MenuItemButton(onPressed: () => onSelected(key), child: Text(value)),
      ],
      builder: (context, controller, _) => FilterChip(
        avatar: Icon(icon, size: 18),
        label: Text(label),
        selected: selected,
        onSelected: (_) => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

class _NotesBody extends StatelessWidget {
  const _NotesBody({
    required this.pinned,
    required this.others,
    required this.layout,
    required this.view,
    required this.isFiltering,
    required this.hasAnyNotes,
    required this.tagNames,
    required this.onOpen,
    required this.onLongPress,
    required this.onSwipe,
  });

  final List<Note> pinned;
  final List<Note> others;
  final NotesLayout layout;
  final NotesView view;
  final bool isFiltering;
  final bool hasAnyNotes;
  final Map<String, String> tagNames;
  final ValueChanged<Note> onOpen;
  final ValueChanged<Note> onLongPress;
  final ValueChanged<Note> onSwipe;

  @override
  Widget build(BuildContext context) {
    if (pinned.isEmpty && others.isEmpty) return _empty(context);

    final slivers = <Widget>[];
    void section(String? heading, List<Note> notes) {
      if (notes.isEmpty) return;
      if (heading != null) {
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
              child: Semantics(
                header: true,
                child: Text(heading, style: Theme.of(context).textTheme.labelLarge),
              ),
            ),
          ),
        );
      }
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          sliver: layout == NotesLayout.grid
              ? SliverMasonryGrid.count(
                  crossAxisCount: MediaQuery.sizeOf(context).width >= 900
                      ? 4
                      : MediaQuery.sizeOf(context).width >= 600
                      ? 3
                      : 2,
                  mainAxisSpacing: AppSpacing.sm,
                  crossAxisSpacing: AppSpacing.sm,
                  childCount: notes.length,
                  itemBuilder: (context, index) => _card(notes[index], compact: false),
                )
              : SliverList.separated(
                  itemCount: notes.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) => _swipeable(context, notes[index]),
                ),
        ),
      );
    }

    final showHeadings = pinned.isNotEmpty;
    section(showHeadings ? 'Pinned' : null, pinned);
    section(showHeadings && others.isNotEmpty ? 'Others' : null, others);
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 140)));
    return CustomScrollView(slivers: slivers);
  }

  Widget _card(Note note, {required bool compact}) => NoteCard(
    key: ValueKey('card_${note.id}'),
    note: note,
    tagNames: [for (final id in note.tagIds) ?tagNames[id]],
    compact: compact,
    onTap: () => onOpen(note),
    onLongPress: () => onLongPress(note),
  );

  Widget _swipeable(BuildContext context, Note note) {
    final card = _card(note, compact: true);
    if (view == NotesView.trash) return card;
    final scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey('swipe_${note.id}'),
      background: Container(
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Icon(
          note.archived ? Icons.unarchive_outlined : Icons.archive_outlined,
          color: scheme.onSecondaryContainer,
        ),
      ),
      secondaryBackground: Container(
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Icon(
          note.archived ? Icons.unarchive_outlined : Icons.archive_outlined,
          color: scheme.onSecondaryContainer,
        ),
      ),
      confirmDismiss: (_) async {
        onSwipe(note);
        return false; // The list redraws from the store.
      },
      child: card,
    );
  }

  Widget _empty(BuildContext context) {
    final (icon, text) = isFiltering
        ? (Icons.search_off, 'No notes match your search or filter.')
        : switch (view) {
            NotesView.notes => (
              Icons.note_add_outlined,
              hasAnyNotes ? 'No notes here yet.' : 'No notes yet. Tap + to create one.',
            ),
            NotesView.reminders => (Icons.notifications_none, 'Notes with reminders appear here.'),
            NotesView.archive => (Icons.archive_outlined, 'Your archived notes appear here.'),
            NotesView.trash => (Icons.delete_outline, 'No notes in Trash.'),
          };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: AppSpacing.sm),
            Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
