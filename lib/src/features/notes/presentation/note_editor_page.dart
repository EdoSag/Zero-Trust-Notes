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
import '../domain/note.dart';

enum _SaveStatus { idle, saving, saved }

class NoteEditorPage extends ConsumerStatefulWidget {
  const NoteEditorPage({super.key, this.note});

  final Note? note;

  @override
  ConsumerState<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends ConsumerState<NoteEditorPage> {
  late final TextEditingController _titleController =
      TextEditingController(text: widget.note?.title ?? '');
  late final TextEditingController _bodyController =
      TextEditingController(text: widget.note?.body ?? '');

  Note? _note;
  String? _notebookId;
  List<String> _tagIds = const [];
  DateTime? _lastSavedAt;
  Timer? _debounce;
  _SaveStatus _status = _SaveStatus.idle;
  bool _dirty = false;
  bool _previewMode = false;

  bool get _isEditing => _note != null;

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _notebookId = widget.note?.notebookId;
    _tagIds = widget.note?.tagIds ?? const [];
    _lastSavedAt = widget.note?.updatedAt;
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

  void _onTextChanged() {
    _dirty = true;
    setState(() => _status = _SaveStatus.saving);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), _persist);
  }

  Future<void> _persist() async {
    _debounce?.cancel();
    if (!_dirty) return;
    final repository = ref.read(notesRepositoryProvider);
    if (repository == null) return;

    final title = _titleController.text;
    final body = _bodyController.text;
    _dirty = false;

    if (_note == null) {
      _note = await repository.createNote(
        title: title,
        body: body,
        notebookId: _notebookId,
        tagIds: _tagIds,
      );
    } else {
      final updated = _note!.copyWith(
        title: title,
        body: body,
        notebookId: _notebookId,
        tagIds: _tagIds,
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
    _debounce?.cancel();
    _dirty = true;
    _persist();
  }

  void _setTags(List<String> tagIds) {
    setState(() => _tagIds = tagIds);
    _debounce?.cancel();
    _dirty = true;
    _persist();
  }

  Future<void> _delete() async {
    final repository = ref.read(notesRepositoryProvider);
    if (repository == null || _note == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete note?'),
        content: const Text('You can undo this from the notes list right after deleting.'),
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

    await repository.deleteNote(_note!.id);
    if (mounted) Navigator.of(context).pop();
  }

  int get _wordCount {
    final text = _bodyController.text.trim();
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
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _saveAndClose,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _saveAndClose,
        const SingleActivator(LogicalKeyboardKey.escape): _saveAndClose,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: Semantics(
              header: true,
              child: Text(_isEditing ? 'Edit note' : 'New note'),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Center(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _statusLabel,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ),
              AccessibleIconButton(
                label: _previewMode ? 'Edit body' : 'Preview body',
                icon: _previewMode ? Icons.edit_outlined : Icons.visibility_outlined,
                onPressed: () => setState(() => _previewMode = !_previewMode),
              ),
              if (_isEditing) ...[
                AccessibleIconButton(
                  label: 'Export note',
                  icon: Icons.ios_share,
                  onPressed: () => showExportSheet(context, singleNote: _note),
                ),
                AccessibleIconButton(
                  label: 'Delete note',
                  icon: Icons.delete_outline,
                  onPressed: _delete,
                ),
              ],
              AccessibleIconButton(
                label: 'Save and close',
                icon: Icons.check,
                onPressed: _saveAndClose,
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  textField: true,
                  label: 'Note title',
                  child: TextField(
                    key: const Key('note_title_field'),
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    NotebookField(notebookId: _notebookId, onChanged: _setNotebook),
                    TagField(tagIds: _tagIds, onChanged: _setTags),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Expanded(
                  child: _previewMode
                      ? Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          decoration: BoxDecoration(
                            border: Border.all(color: Theme.of(context).colorScheme.outline),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: _bodyController.text.trim().isEmpty
                              ? Text(
                                  'Nothing to preview yet.',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                )
                              : Markdown(
                                  data: _bodyController.text,
                                  selectable: true,
                                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
                                ),
                        )
                      : Semantics(
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
                        ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _footerText(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
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
