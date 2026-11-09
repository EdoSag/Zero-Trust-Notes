import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/app_spacing.dart';
import '../../../shared/widgets/accessible_touch_target.dart';
import '../../export/presentation/export_sheet.dart';
import '../../notebooks/presentation/notebook_picker.dart';
import '../../tags/presentation/tag_picker.dart';
import '../application/notes_providers.dart';
import '../data/notes_repository.dart';
import '../domain/checklist_item.dart';
import '../domain/note.dart';
import '../domain/note_color.dart';
import 'checklist_editor.dart';
import 'note_actions.dart';

enum _SaveStatus { idle, saving, saved }

class NoteEditorPage extends ConsumerStatefulWidget {
  const NoteEditorPage({
    super.key,
    this.note,
    this.startAsChecklist = false,
    this.initialNotebookId,
    this.initialTagId,
    this.archived = false,
  });

  final Note? note;

  /// For a new note: start with checkboxes.
  final bool startAsChecklist;

  /// For a new note made while a notebook or tag is shown.
  final String? initialNotebookId;
  final String? initialTagId;

  /// For a new note made in the Archive view.
  final bool archived;

  @override
  ConsumerState<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends ConsumerState<NoteEditorPage> {
  late final TextEditingController _titleController = TextEditingController(
    text: widget.note?.title ?? '',
  );
  late final TextEditingController _bodyController = TextEditingController(
    text: widget.note?.isChecklist ?? false ? '' : widget.note?.body ?? '',
  );

  Note? _note;
  String? _notebookId;
  List<String> _tagIds = const [];
  bool _pinned = false;
  bool _archived = false;
  NoteColor _color = NoteColor.none;
  List<ChecklistItem>? _checklist;
  DateTime? _reminderAt;
  DateTime? _lastSavedAt;
  Timer? _debounce;
  _SaveStatus _status = _SaveStatus.idle;
  bool _dirty = false;
  bool _previewMode = false;

  /// Saves run one after another, so a quick second edit can't create the
  /// note twice.
  Future<void> _saving = Future.value();

  bool get _isEditing => _note != null;
  bool get _inTrash => _note?.isTrashed ?? false;

  @override
  void initState() {
    super.initState();
    final note = widget.note;
    _note = note;
    _notebookId = note?.notebookId ?? widget.initialNotebookId;
    _tagIds = note?.tagIds ?? [?widget.initialTagId];
    _pinned = note?.pinned ?? false;
    _archived = note?.archived ?? widget.archived;
    _color = note?.color ?? NoteColor.none;
    _checklist = note?.checklist ?? (widget.startAsChecklist && note == null ? const [] : null);
    _reminderAt = note?.reminderAt;
    _lastSavedAt = note?.updatedAt;
    _titleController.addListener(_onTextChanged);
    _bodyController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _onTextChanged() => _changed(debounce: true);

  /// Marks the note changed; text edits wait a moment, other changes save
  /// at once.
  void _changed({bool debounce = false}) {
    if (_inTrash) return;
    _dirty = true;
    setState(() => _status = _SaveStatus.saving);
    _debounce?.cancel();
    if (debounce) {
      _debounce = Timer(const Duration(milliseconds: 800), _persist);
    } else {
      _persist();
    }
  }

  String get _body => _checklist != null
      ? ChecklistItem.toMarkdown(ChecklistItem.ordered(_checklist!))
      : _bodyController.text;

  bool get _isBlank =>
      _titleController.text.trim().isEmpty &&
      _body.trim().isEmpty &&
      (_checklist?.every((item) => item.text.trim().isEmpty) ?? true);

  Future<void> _persist() {
    _debounce?.cancel();
    // Read now: this also runs as the page pops, after which `ref` is gone.
    final repository = ref.read(notesRepositoryProvider);
    return _saving = _saving.then((_) => _persistNow(repository)).catchError((Object _) {
      if (mounted) setState(() => _status = _SaveStatus.idle);
    });
  }

  Future<void> _persistNow(NotesRepository? repository) async {
    if (!_dirty || repository == null) return;
    // Don't create an empty note just because the editor was opened.
    if (_note == null && _isBlank) {
      _dirty = false;
      return;
    }
    _dirty = false;

    final checklist = _checklist == null ? null : ChecklistItem.ordered(_checklist!);
    if (_note == null) {
      _note = await repository.createNote(
        title: _titleController.text,
        body: _body,
        notebookId: _notebookId,
        tagIds: _tagIds,
        pinned: _pinned,
        color: _color,
        archived: _archived,
        checklist: checklist,
        reminderAt: _reminderAt,
      );
    } else {
      final updated = _note!.copyWith(
        title: _titleController.text,
        body: _body,
        notebookId: _notebookId,
        tagIds: _tagIds,
        pinned: _pinned,
        color: _color,
        archived: _archived,
        checklist: checklist,
        reminderAt: _reminderAt,
      );
      await repository.updateNote(updated);
      _note = updated;
    }
    _lastSavedAt = DateTime.now();
    if (mounted) setState(() => _status = _SaveStatus.saved);
  }

  Future<void> _saveAndClose() async {
    await _persist();
    if (mounted) Navigator.of(context).pop();
  }

  void _setNotebook(String? notebookId) {
    setState(() => _notebookId = notebookId);
    _changed();
  }

  void _setTags(List<String> tagIds) {
    setState(() => _tagIds = tagIds);
    _changed();
  }

  void _togglePin() {
    setState(() {
      _pinned = !_pinned;
      if (_pinned) _archived = false;
    });
    _changed();
  }

  Future<void> _toggleArchive() async {
    setState(() {
      _archived = !_archived;
      if (_archived) _pinned = false;
    });
    _changed();
    await _saving;
    if (!mounted) return;
    final wasArchived = _archived;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(wasArchived ? 'Note archived' : 'Note unarchived')),
    );
    if (wasArchived) Navigator.of(context).pop();
  }

  Future<void> _pickColor() async {
    final color = await showNoteColorPicker(context, _color);
    if (color == null || color == _color) return;
    setState(() => _color = color);
    _changed();
  }

  Future<void> _pickReminder() async {
    final choice = await showReminderPicker(context, ref, _reminderAt);
    if (choice == null) return;
    setState(() => _reminderAt = choice.at);
    _changed();
  }

  void _toggleChecklist() {
    setState(() {
      if (_checklist == null) {
        _checklist = ChecklistItem.parseLines(_bodyController.text);
        _bodyController.removeListener(_onTextChanged);
        _bodyController.clear();
        _bodyController.addListener(_onTextChanged);
        _previewMode = false;
      } else {
        final text = [for (final item in _checklist!) item.text].join('\n');
        _checklist = null;
        _bodyController.removeListener(_onTextChanged);
        _bodyController.text = text;
        _bodyController.addListener(_onTextChanged);
      }
    });
    _changed();
  }

  void _onChecklistChanged(List<ChecklistItem> items, {required bool typing}) {
    setState(() => _checklist = items);
    _changed(debounce: typing);
  }

  Future<void> _moveToTrash() async {
    await _persist();
    final note = _note;
    if (note == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (!mounted) return;
    final actions = NoteActions(context, ref);
    Navigator.of(context).pop();
    await actions.moveToTrash(note);
  }

  Future<void> _restore() async {
    final note = _note;
    if (note == null) return;
    final restored = await NoteActions(context, ref).restore(note);
    if (restored != null && mounted) setState(() => _note = restored);
  }

  Future<void> _deleteForever() async {
    final note = _note;
    if (note == null) return;
    if (await NoteActions(context, ref).deleteForever(note) && mounted) {
      Navigator.of(context).pop();
    }
  }

  int get _wordCount {
    final text = _body.trim();
    if (text.isEmpty) return 0;
    return text.split(RegExp(r'\s+')).length;
  }

  String get _statusLabel => switch (_status) {
    _SaveStatus.idle => '',
    _SaveStatus.saving => 'Saving…',
    _SaveStatus.saved => 'Saved',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = _color.background(theme.brightness);
    final isChecklist = _checklist != null;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _saveAndClose,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _saveAndClose,
        const SingleActivator(LogicalKeyboardKey.escape): _saveAndClose,
      },
      child: Focus(
        autofocus: true,
        child: PopScope(
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) _persist();
          },
          child: Scaffold(
            backgroundColor: background,
            appBar: AppBar(
              backgroundColor: background,
              title: Semantics(
                header: true,
                child: Text(_inTrash ? 'In Trash' : (_isEditing ? 'Edit note' : 'New note')),
              ),
              actions: _inTrash ? _trashActions() : _editActions(isChecklist),
            ),
            body: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_inTrash)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Text(
                        'Notes in Trash can\'t be edited. Restore it to make changes.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  Semantics(
                    textField: true,
                    label: 'Note title',
                    child: TextField(
                      key: const Key('note_title_field'),
                      controller: _titleController,
                      readOnly: _inTrash,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (!_inTrash)
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        NotebookField(notebookId: _notebookId, onChanged: _setNotebook),
                        TagField(tagIds: _tagIds, onChanged: _setTags),
                        if (_reminderAt != null)
                          InputChip(
                            avatar: const Icon(Icons.alarm, size: 18),
                            label: Text(formatReminder(_reminderAt!)),
                            onPressed: _pickReminder,
                            onDeleted: () {
                              setState(() => _reminderAt = null);
                              _changed();
                            },
                            deleteButtonTooltipMessage: 'Remove reminder',
                          ),
                      ],
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  Expanded(child: isChecklist ? _checklistBody() : _textBody(theme)),
                  const SizedBox(height: AppSpacing.xs),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _footerText(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _trashActions() => [
    AccessibleIconButton(
      label: 'Restore',
      icon: Icons.restore_from_trash_outlined,
      onPressed: _restore,
    ),
    AccessibleIconButton(
      label: 'Delete forever',
      icon: Icons.delete_forever_outlined,
      onPressed: _deleteForever,
    ),
  ];

  List<Widget> _editActions(bool isChecklist) => [
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Center(
        child: Semantics(
          liveRegion: true,
          child: Text(_statusLabel, style: Theme.of(context).textTheme.bodySmall),
        ),
      ),
    ),
    AccessibleIconButton(
      label: _pinned ? 'Unpin note' : 'Pin note',
      icon: _pinned ? Icons.push_pin : Icons.push_pin_outlined,
      onPressed: _togglePin,
    ),
    AccessibleIconButton(
      label: _reminderAt == null ? 'Remind me' : 'Change reminder',
      icon: _reminderAt == null ? Icons.add_alert_outlined : Icons.notifications_active_outlined,
      onPressed: _pickReminder,
    ),
    AccessibleIconButton(
      label: _archived ? 'Unarchive note' : 'Archive note',
      icon: _archived ? Icons.unarchive_outlined : Icons.archive_outlined,
      onPressed: _toggleArchive,
    ),
    PopupMenuButton<String>(
      tooltip: 'More options',
      onSelected: (value) {
        switch (value) {
          case 'color':
            _pickColor();
          case 'checklist':
            _toggleChecklist();
          case 'preview':
            setState(() => _previewMode = !_previewMode);
          case 'export':
            if (_note != null) showExportSheet(context, singleNote: _note);
          case 'trash':
            _moveToTrash();
          case 'save':
            _saveAndClose();
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'color',
          child: ListTile(leading: Icon(Icons.palette_outlined), title: Text('Colour')),
        ),
        PopupMenuItem(
          value: 'checklist',
          child: ListTile(
            leading: Icon(isChecklist ? Icons.notes : Icons.checklist),
            title: Text(isChecklist ? 'Hide checkboxes' : 'Show checkboxes'),
          ),
        ),
        if (!isChecklist)
          PopupMenuItem(
            value: 'preview',
            child: ListTile(
              leading: Icon(_previewMode ? Icons.edit_outlined : Icons.visibility_outlined),
              title: Text(_previewMode ? 'Edit text' : 'Preview Markdown'),
            ),
          ),
        if (_isEditing)
          const PopupMenuItem(
            value: 'export',
            child: ListTile(leading: Icon(Icons.ios_share), title: Text('Export note')),
          ),
        if (_isEditing)
          const PopupMenuItem(
            value: 'trash',
            child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Move to Trash')),
          ),
        const PopupMenuItem(
          value: 'save',
          child: ListTile(leading: Icon(Icons.check), title: Text('Save and close')),
        ),
      ],
    ),
  ];

  Widget _checklistBody() => ChecklistEditor(
    items: _checklist!,
    readOnly: _inTrash,
    onChanged: _onChecklistChanged,
  );

  Widget _textBody(ThemeData theme) {
    if (_previewMode || _inTrash) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outline),
          borderRadius: BorderRadius.circular(4),
        ),
        child: _bodyController.text.trim().isEmpty
            ? Text(
                'Nothing to preview yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            : Markdown(
                data: _bodyController.text,
                selectable: true,
                styleSheet: MarkdownStyleSheet.fromTheme(theme),
              ),
      );
    }
    return Semantics(
      textField: true,
      label: 'Note body',
      child: TextField(
        key: const Key('note_body_field'),
        controller: _bodyController,
        decoration: const InputDecoration(
          labelText: 'Body (Markdown supported)',
          border: OutlineInputBorder(),
          alignLabelWithHint: true,
        ),
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
      ),
    );
  }

  String _footerText() {
    final words = '$_wordCount word${_wordCount == 1 ? '' : 's'}';
    if (_lastSavedAt == null) return words;
    return '$words · Edited ${_relativeTime(_lastSavedAt!)}';
  }

  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 10) return 'just now';
    if (diff.inMinutes < 1) return '${diff.inSeconds}s ago';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
  }
}
