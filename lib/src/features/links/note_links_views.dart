import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';

import '../../shared/markdown_snippet.dart';
import '../notes/application/notes_providers.dart';
import '../notes/domain/note.dart';
import 'note_links.dart';

/// Picks a note to link to: every note outside Trash but [exceptId],
/// searchable by title and text. Returns the picked note.
Future<Note?> showNoteLinkPicker(BuildContext context, {String? exceptId}) =>
    showModalBottomSheet<Note>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NoteLinkPicker(exceptId: exceptId),
    );

class _NoteLinkPicker extends ConsumerStatefulWidget {
  const _NoteLinkPicker({this.exceptId});

  final String? exceptId;

  @override
  ConsumerState<_NoteLinkPicker> createState() => _NoteLinkPickerState();
}

class _NoteLinkPickerState extends ConsumerState<_NoteLinkPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final query = _query.trim().toLowerCase();
    final notes = [
      for (final note in ref.watch(notesListProvider).value ?? const <Note>[])
        if (note.id != widget.exceptId &&
            note.title.trim().isNotEmpty &&
            (query.isEmpty ||
                note.title.toLowerCase().contains(query) ||
                (!note.locked && note.body.toLowerCase().contains(query))))
          note,
    ];
    final height = MediaQuery.sizeOf(context).height * 0.7;
    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(l10n.linkToNote, style: Theme.of(context).textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                key: const Key('note_link_search'),
                autofocus: true,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: l10n.searchNotesToLink,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: notes.isEmpty
                  ? Center(child: Text(l10n.noNotesToLink, textAlign: TextAlign.center))
                  : ListView.builder(
                      itemCount: notes.length,
                      itemBuilder: (context, i) {
                        final note = notes[i];
                        return ListTile(
                          key: ValueKey('note_link_${note.id}'),
                          leading: Icon(note.isChecklist ? Icons.checklist : Icons.notes),
                          title: Text(note.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: note.locked
                              ? Text(l10n.lockedNote)
                              : Text(
                                  stripMarkdownForSnippet(note.body),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          onTap: () => Navigator.of(context).pop(note),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The notes this note links to, and the notes that link to it, as chips
/// under the text. A link to a note that doesn't exist yet offers to make
/// it. Nothing shows when there are no links either way.
class NoteLinksBar extends ConsumerWidget {
  const NoteLinksBar({
    super.key,
    required this.noteId,
    required this.title,
    required this.body,
    required this.onOpen,
    required this.onCreate,
  });

  final String? noteId;
  final String title;
  final String body;
  final void Function(Note note) onOpen;
  final void Function(String title) onCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(allNotesProvider).value ?? const <Note>[];
    final outgoing = NoteLinks.titles(body);
    final incoming = NoteLinks.backlinks(title, noteId, notes);
    if (outgoing.isEmpty && incoming.isEmpty) return const SizedBox.shrink();
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SingleChildScrollView(
        key: const Key('note_links_bar'),
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Icon(Icons.link, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            for (final linked in outgoing) ...[
              Builder(
                builder: (context) {
                  final target = NoteLinks.resolve(linked, notes, exceptId: noteId);
                  return ActionChip(
                    key: ValueKey('note_link_out_$linked'),
                    avatar: Icon(target == null ? Icons.add : Icons.north_east, size: 16),
                    label: Text(linked),
                    tooltip: target == null ? l10n.createLinkedNote(linked) : l10n.openLinkedNote(linked),
                    onPressed: () => target == null ? onCreate(linked) : onOpen(target),
                  );
                },
              ),
              const SizedBox(width: 6),
            ],
            for (final from in incoming) ...[
              ActionChip(
                key: ValueKey('note_link_in_${from.id}'),
                avatar: const Icon(Icons.south_west, size: 16),
                label: Text(from.title.isEmpty ? l10n.untitled : from.title),
                tooltip: l10n.linksHere(from.title.isEmpty ? l10n.untitled : from.title),
                onPressed: () => onOpen(from),
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }
}
