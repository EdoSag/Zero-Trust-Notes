import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/accessible_touch_target.dart';
import '../../export/presentation/export_sheet.dart';
import '../application/notes_session.dart';
import '../domain/note.dart';

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

  bool get _isEditing => widget.note != null;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          header: true,
          child: Text(_isEditing ? 'Edit note' : 'New note'),
        ),
        actions: [
          if (_isEditing) ...[
            AccessibleIconButton(
              label: 'Export note',
              icon: Icons.ios_share,
              onPressed: () => showExportSheet(context, singleNote: widget.note),
            ),
            AccessibleIconButton(
              label: 'Delete note',
              icon: Icons.delete_outline,
              onPressed: _delete,
            ),
          ],
          AccessibleIconButton(
            label: 'Save note',
            icon: Icons.check,
            onPressed: _save,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
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
            const SizedBox(height: 12),
            Expanded(
              child: Semantics(
                textField: true,
                label: 'Note body',
                child: TextField(
                  key: const Key('note_body_field'),
                  controller: _bodyController,
                  decoration: const InputDecoration(
                    labelText: 'Body',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final repository = ref.read(notesRepositoryProvider);
    if (repository == null) return;

    final title = _titleController.text;
    final body = _bodyController.text;

    if (_isEditing) {
      await repository.updateNote(widget.note!.copyWith(title: title, body: body));
    } else {
      await repository.createNote(title: title, body: body);
    }

    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final repository = ref.read(notesRepositoryProvider);
    if (repository == null || widget.note == null) return;

    await repository.deleteNote(widget.note!.id);
    if (mounted) Navigator.of(context).pop();
  }
}
