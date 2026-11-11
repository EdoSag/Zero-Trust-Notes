import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zt_sharing_ui/zt_sharing_ui.dart';

import '../../../shared/theme/app_spacing.dart';
import '../../../shared/widgets/accessible_touch_target.dart';
import '../../keep_import/keep_import_flow.dart';
import '../../legacy_import/presentation/legacy_import.dart';
import '../../notebooks/application/notebooks_controller.dart';
import '../../notebooks/domain/notebook.dart';
import '../../settings/notes_settings_page.dart';
import '../../sharing/shared_notebooks.dart';
import '../../sharing/sharing_flows.dart';
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
import 'package:zerotrust_notes/l10n/l10n.dart';

enum _SortOption {
  custom,
  updatedDesc,
  updatedAsc,
  createdDesc,
  createdAsc,
  titleAsc;

  String label(AppL10n l) => switch (this) {
    custom => l.sortCustom,
    updatedDesc => l.sortUpdatedDesc,
    updatedAsc => l.sortUpdatedAsc,
    createdDesc => l.sortCreatedDesc,
    createdAsc => l.sortCreatedAsc,
    titleAsc => l.sortTitle,
  };
}

class NotesListPage extends ConsumerStatefulWidget {
  const NotesListPage({super.key});

  @override
  ConsumerState<NotesListPage> createState() => _NotesListPageState();
}

class _NotesListPageState extends ConsumerState<NotesListPage> {
  final _searchController = TextEditingController();
  bool _searchActive = false;

  /// Like Keep: new and edited notes on top, and notes stay where they're
  /// dragged.
  _SortOption _sort = _SortOption.custom;
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
        _SortOption.custom => b.orderKey.compareTo(a.orderKey),
        _SortOption.updatedDesc => b.updatedAt.compareTo(a.updatedAt),
        _SortOption.updatedAsc => a.updatedAt.compareTo(b.updatedAt),
        _SortOption.createdDesc => b.createdAt.compareTo(a.createdAt),
        _SortOption.createdAsc => a.createdAt.compareTo(b.createdAt),
        _SortOption.titleAsc => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      },
    );
    return list;
  }

  /// Puts [moved] where [target] is in [section] (the notes as shown):
  /// before it when moving up, after it when moving down. Only [moved]
  /// changes, so other devices merge the move like any edit.
  Future<void> _reorder(List<Note> section, Note moved, Note target) async {
    final position = reorderPosition(section, moved, target);
    if (position == null) return;
    await ref.read(notesRepositoryProvider)?.updateNote(moved.copyWith(position: position));
  }

  void _open(Note note) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => NoteEditorPage(note: note)));

  void _create({bool checklist = false, bool voice = false}) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => NoteEditorPage(
        startAsChecklist: checklist,
        startWithVoice: voice,
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
        title: Text(context.l10n.emptyTrashQ),
        content: Text(
          context.l10n.emptyTrashBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.emptyTrash),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(notesRepositoryProvider)?.emptyTrash();
  }

  String get _title => switch (_filter.view) {
    NotesView.notes => context.l10n.viewNotes,
    NotesView.reminders => context.l10n.viewReminders,
    NotesView.archive => context.l10n.viewArchive,
    NotesView.trash => context.l10n.viewTrash,
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
          SnackBar(
            content: Text(
              context.l10n.syncFailed,
            ),
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
            onSharedSpace: (spaceId) => openSharedSpace(context, ref, spaceId),
            onJoin: () => openJoinShared(context, ref),
          ),
          appBar: AppBar(
            title: _searchActive
                ? Semantics(
                    textField: true,
                    label: context.l10n.searchNotes,
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: context.l10n.searchIn(_title.toLowerCase()),
                        border: InputBorder.none,
                      ),
                    ),
                  )
                : Semantics(header: true, child: Text(_heading(notebooks, tags))),
            actions: [
              AccessibleIconButton(
                label: _searchActive ? context.l10n.closeSearch : context.l10n.searchNotes,
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
                label: layout == NotesLayout.grid ? context.l10n.showAsList : context.l10n.showAsGrid,
                icon: layout == NotesLayout.grid ? Icons.view_agenda_outlined : Icons.grid_view,
                onPressed: () => ref.read(notesLayoutProvider.notifier).toggle(),
              ),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: SyncStatusBadge()),
              PopupMenuButton<Object>(
                tooltip: context.l10n.moreOptions,
                onSelected: (value) {
                  if (value is _SortOption) setState(() => _sort = value);
                  if (value == 'empty') _emptyTrash();
                  if (value == 'share') _shareNotebook(notebooks);
                },
                itemBuilder: (context) => [
                  if (_filter.notebookId != null && notebooks.any((n) => n.id == _filter.notebookId))
                    PopupMenuItem(
                      key: const Key('notebook_share'),
                      value: 'share',
                      child: Text(
                        Notebook.spaceIdOf(_filter.notebookId) != null
                            ? ZtSharingStrings.of(context).peopleAndSharing
                            : context.l10n.shareNotebook,
                      ),
                    ),
                  if (_filter.view == NotesView.trash)
                    PopupMenuItem(value: 'empty', child: Text(context.l10n.emptyTrash)),
                  if (_filter.view == NotesView.notes || _filter.view == NotesView.archive)
                    for (final option in _SortOption.values)
                      CheckedPopupMenuItem(
                        value: option,
                        checked: option == _sort,
                        child: Text(option.label(context.l10n)),
                      ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              const LegacyImportBanner(),
              const SharedJoinRequests(),
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
                    context.l10n.trashAfter30,
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
                      // Dragging works in the main and Archive views in
                      // custom order, where a moved note stays put.
                      onReorder:
                          _sort == _SortOption.custom &&
                              (_filter.view == NotesView.notes || _filter.view == NotesView.archive)
                          ? (section, moved, target) => _reorder(section, moved, target)
                          : null,
                      onSwipe: (note) => NoteActions(context, ref).toggleArchive(note),
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(child: Text(context.l10n.failedNotes('$error'))),
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
                      heroTag: 'new_voice',
                      tooltip: context.l10n.newVoiceNote,
                      onPressed: () => _create(voice: true),
                      child: const Icon(Icons.mic_none),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    FloatingActionButton.small(
                      heroTag: 'new_list',
                      tooltip: context.l10n.newChecklist,
                      onPressed: () => _create(checklist: true),
                      child: const Icon(Icons.checklist),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    FloatingActionButton(
                      heroTag: 'new_note',
                      tooltip: context.l10n.createNote,
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

  Future<void> _shareNotebook(List<Notebook> notebooks) async {
    final notebook = notebooks.where((n) => n.id == _filter.notebookId).firstOrNull;
    if (notebook == null) return;
    final id = await shareNotebookFlow(context, ref, notebook);
    if (id != null && mounted && id != notebook.id) {
      setState(() => _filter = NotesFilter(notebookId: id));
    }
  }

  String _heading(List<Notebook> notebooks, List<Tag> tags) {
    if (_filter.tagId != null) {
      return tags.where((tag) => tag.id == _filter.tagId).firstOrNull?.name ?? context.l10n.tag;
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
    required this.onSharedSpace,
    required this.onJoin,
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

  /// Opens a shared space that has no notebook to show yet (waiting to be
  /// let in). Runs on the notes page.
  final ValueChanged<String> onSharedSpace;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sharing = ref.watch(sharedNotesProvider);
    final waiting = [
      for (final n in sharing.notebooks)
        if (n.shared!.waiting) n,
    ];
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
          padding: const EdgeInsetsDirectional.fromSTEB(28, 16, 16, 8),
          child: Text('ZT Notes', style: Theme.of(context).textTheme.titleLarge),
        ),
        viewTile(NotesView.notes, Icons.lightbulb_outline, context.l10n.viewNotes),
        viewTile(NotesView.reminders, Icons.notifications_none, context.l10n.viewReminders),
        if (notebooks.isNotEmpty) ...[
          const Divider(),
          _DrawerHeading(context.l10n.notebooks),
          for (final notebook in notebooks)
            ListTile(
              leading: Icon(notebook.isShared ? Icons.folder_shared_outlined : Icons.book_outlined),
              title: Text(notebook.name),
              selected: filter.notebookId == notebook.id,
              onTap: () => onNotebook(notebook.id),
            ),
        ],
        if (waiting.isNotEmpty) ...[
          const Divider(),
          _DrawerHeading(context.l10n.sharedHeading),
          for (final notebook in waiting)
            ListTile(
              leading: const Icon(Icons.hourglass_top),
              title: Text(ZtSharingStrings.of(context).waitingToJoin),
              onTap: () {
                Navigator.of(context).pop();
                onSharedSpace(notebook.shared!.spaceId);
              },
            ),
        ],
        if (tags.isNotEmpty) ...[
          const Divider(),
          _DrawerHeading(context.l10n.tags),
          for (final tag in tags)
            ListTile(
              leading: const Icon(Icons.label_outline),
              title: Text(tag.name),
              selected: filter.tagId == tag.id,
              onTap: () => onTag(tag.id),
            ),
        ],
        const Divider(),
        viewTile(NotesView.archive, Icons.archive_outlined, context.l10n.viewArchive),
        viewTile(NotesView.trash, Icons.delete_outline, context.l10n.viewTrash),
        const Divider(),
        if (sharing.available)
          ListTile(
            key: const Key('drawer_join_shared'),
            leading: const Icon(Icons.group_add_outlined),
            title: Text(context.l10n.joinWithInvite),
            onTap: () {
              Navigator.of(context).pop();
              onJoin();
            },
          ),
        ListTile(
          leading: const Icon(Icons.download_outlined),
          title: Text(context.l10n.importFromKeep),
          onTap: () {
            Navigator.of(context).pop();
            onImportFromKeep();
          },
        ),
        ListTile(
          leading: const Icon(Icons.settings_outlined),
          title: Text(context.l10n.settings),
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
    padding: const EdgeInsetsDirectional.fromSTEB(28, 8, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

/// Notebook chips above the main Notes view.
class _NotebookFilterBar extends StatelessWidget {
  const _NotebookFilterBar({
    required this.filter,
    required this.notebooks,
    required this.onChanged,
  });

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
            padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
            child: ChoiceChip(
              label: Text(context.l10n.all),
              selected: all,
              onSelected: (_) => onChanged(filter.copyWith(notebookId: null, unfiledOnly: false)),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
            child: ChoiceChip(
              label: Text(context.l10n.unfiled),
              selected: filter.unfiledOnly,
              onSelected: (_) => onChanged(filter.copyWith(notebookId: null, unfiledOnly: true)),
            ),
          ),
          for (final notebook in notebooks)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
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
    Widget gap(Widget child) => Padding(
      padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
      child: child,
    );

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        children: [
          gap(
            FilterChip(
              avatar: const Icon(Icons.checklist, size: 18),
              label: Text(context.l10n.checklists),
              selected: filter.checklistsOnly,
              onSelected: (on) => onChanged(filter.copyWith(checklistsOnly: on)),
            ),
          ),
          gap(
            FilterChip(
              avatar: const Icon(Icons.alarm, size: 18),
              label: Text(context.l10n.viewReminders),
              selected: filter.withReminderOnly,
              onSelected: (on) => onChanged(filter.copyWith(withReminderOnly: on)),
            ),
          ),
          gap(
            FilterChip(
              avatar: filter.color == null
                  ? const Icon(Icons.palette_outlined, size: 18)
                  : CircleAvatar(backgroundColor: filter.color!.background(brightness)),
              label: Text(filter.color?.displayName ?? context.l10n.colour),
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
                label: tagName ?? context.l10n.tag,
                selected: filter.tagId != null,
                options: {for (final tag in tags) tag.id: tag.name},
                onSelected: (id) => onChanged(filter.copyWith(tagId: id)),
              ),
            ),
          if (notebooks.isNotEmpty)
            gap(
              _MenuChip<String>(
                icon: Icons.book_outlined,
                label: notebookName ?? context.l10n.notebook,
                selected: filter.notebookId != null,
                options: {for (final notebook in notebooks) notebook.id: notebook.name},
                onSelected: (id) => onChanged(filter.copyWith(notebookId: id)),
              ),
            ),
          if (filter.isFiltering)
            TextButton(
              onPressed: () => onChanged(filter.cleared().copyWith(query: filter.query)),
              child: Text(context.l10n.clearFilters),
            ),
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
        if (selected) MenuItemButton(onPressed: () => onSelected(null), child: Text(context.l10n.any)),
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
    this.onReorder,
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

  /// Null where notes can't be dragged (another sort, Trash, Reminders).
  final void Function(List<Note> section, Note moved, Note target)? onReorder;

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
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xs,
              ),
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
                  itemBuilder: (context, index) =>
                      _draggable(notes, notes[index], _card(notes[index], compact: false)),
                )
              : SliverList.separated(
                  itemCount: notes.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) =>
                      _draggable(notes, notes[index], _swipeable(context, notes[index])),
                ),
        ),
      );
    }

    final showHeadings = pinned.isNotEmpty;
    section(showHeadings ? context.l10n.pinned : null, pinned);
    section(showHeadings && others.isNotEmpty ? context.l10n.others : null, others);
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 140)));
    return CustomScrollView(slivers: slivers);
  }

  Widget _draggable(List<Note> section, Note note, Widget child) {
    final reorder = onReorder;
    if (reorder == null) return child;
    return ReorderableNote(
      key: ValueKey('drag_${note.id}'),
      note: note,
      onDropped: (moved) {
        final movedNote = section.where((n) => n.id == moved).firstOrNull;
        if (movedNote != null) reorder(section, movedNote, note);
      },
      onLongPress: () => onLongPress(note),
      child: child,
    );
  }

  Widget _card(Note note, {required bool compact}) => NoteCard(
    key: ValueKey('card_${note.id}'),
    note: note,
    tagNames: [for (final id in note.tagIds) ?tagNames[id]],
    compact: compact,
    onTap: () => onOpen(note),
    // When dragging is on, ReorderableNote turns a still long press into this.
    onLongPress: onReorder == null ? () => onLongPress(note) : null,
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
        alignment: AlignmentDirectional.centerStart,
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
        alignment: AlignmentDirectional.centerEnd,
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
        ? (Icons.search_off, context.l10n.noMatch)
        : switch (view) {
            NotesView.notes => (
              Icons.note_add_outlined,
              hasAnyNotes ? context.l10n.noNotesHere : context.l10n.noNotesYet,
            ),
            NotesView.reminders => (Icons.notifications_none, context.l10n.remindersEmpty),
            NotesView.archive => (Icons.archive_outlined, context.l10n.archiveEmpty),
            NotesView.trash => (Icons.delete_outline, context.l10n.trashEmpty),
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

/// The position that puts [moved] where [target] is in [section] (sorted
/// highest [Note.orderKey] first): just above it when moving up, just
/// below when moving down. Null when nothing would change.
double? reorderPosition(List<Note> section, Note moved, Note target) {
  final from = section.indexWhere((n) => n.id == moved.id);
  final to = section.indexWhere((n) => n.id == target.id);
  if (from < 0 || to < 0 || from == to) return null;
  const step = 60000.0; // a minute, past the last note
  final rest = [
    for (final n in section)
      if (n.id != moved.id) n,
  ];
  final at = rest.indexWhere((n) => n.id == target.id);
  // Index in [rest] that [moved] takes.
  final slot = from < to ? at + 1 : at;
  final above = slot > 0 ? rest[slot - 1].orderKey : null;
  final below = slot < rest.length ? rest[slot].orderKey : null;
  if (above == null) return below! + step;
  if (below == null) return above - step;
  return (above + below) / 2;
}

/// A note that can be dragged onto another to move it there (long press,
/// then drag). A long press without moving opens the actions sheet as
/// before.
class ReorderableNote extends StatefulWidget {
  const ReorderableNote({
    super.key,
    required this.note,
    required this.onDropped,
    required this.onLongPress,
    required this.child,
  });

  final Note note;

  /// Another note (its id) was dropped on this one.
  final ValueChanged<String> onDropped;
  final VoidCallback onLongPress;
  final Widget child;

  @override
  State<ReorderableNote> createState() => _ReorderableNoteState();
}

class _ReorderableNoteState extends State<ReorderableNote> {
  Offset? _start;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != widget.note.id,
      onAcceptWithDetails: (details) => widget.onDropped(details.data),
      builder: (context, candidates, _) {
        final hovered = candidates.isNotEmpty;
        return LayoutBuilder(
          builder: (context, constraints) => Semantics(
            onLongPress: widget.onLongPress,
            child: LongPressDraggable<String>(
              data: widget.note.id,
              hapticFeedbackOnStart: true,
              onDragStarted: () {
                final box = context.findRenderObject() as RenderBox?;
                _start = box?.localToGlobal(Offset.zero);
                setState(() => _dragging = true);
              },
              onDragEnd: (details) {
                setState(() => _dragging = false);
                final start = _start;
                // Held but not moved: the long press it always was.
                if (!details.wasAccepted &&
                    start != null &&
                    (details.offset - start).distance < 16) {
                  widget.onLongPress();
                }
              },
              feedback: Material(
                color: Colors.transparent,
                elevation: 6,
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: constraints.maxWidth,
                  child: Opacity(opacity: 0.9, child: widget.child),
                ),
              ),
              childWhenDragging: Opacity(opacity: 0.3, child: widget.child),
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: hovered && !_dragging
                      ? Border.all(color: scheme.primary, width: 2)
                      : null,
                ),
                child: widget.child,
              ),
            ),
          ),
        );
      },
    );
  }
}
