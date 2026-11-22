import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';

import '../notes/application/notes_providers.dart';
import '../notes/domain/note.dart';

/// One line of a Markdown note body as the text to type: the marks that
/// only shape the line are dropped (heading, bullet, number, quote, task
/// box, `**bold**`, `~~struck~~`, `` `code` ``, links keep their label).
/// Everything else stays exactly as written, so an identifier such as
/// `account_ab_cd` or a password with `*` in it is typed unchanged.
String pickTextOfBodyLine(String line) {
  return line
      .replaceFirst(RegExp(r'^\s*#{1,6}\s+'), '')
      .replaceFirst(RegExp(r'^\s*>\s?'), '')
      .replaceFirst(RegExp(r'^\s*(?:[-*+]|\d+\.)\s+'), '')
      .replaceFirst(RegExp(r'^\s*\[( |x|X)\]\s?'), '')
      .replaceAllMapped(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m[1] ?? '')
      .replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m[1] ?? '')
      .replaceAllMapped(RegExp(r'~~(.+?)~~'), (m) => m[1] ?? '')
      .replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m[1] ?? '')
      .trim();
}

/// The lines of [note] that ZT Keyboard can type: the title, then every
/// non-empty line of the text or checklist, without repeats. The title and
/// checklist items are plain text and are typed exactly as written; lines
/// of the Markdown text go through [pickTextOfBodyLine].
List<String> pickLinesOf(Note note) {
  final lines = <String>[];
  final seen = <String>{};
  void add(String text) {
    if (text.isNotEmpty && seen.add(text)) lines.add(text);
  }

  add(note.title.trim());
  final checklist = note.checklist;
  if (checklist != null) {
    for (final item in checklist) {
      add(item.text.trim());
    }
  } else {
    var fenced = false;
    for (final line in note.body.split('\n')) {
      // Code fences are marks; what is between them is typed as written.
      if (line.trimLeft().startsWith('```')) {
        fenced = !fenced;
        continue;
      }
      add(fenced ? line.trim() : pickTextOfBodyLine(line));
    }
  }
  return lines;
}

/// The notes the keyboard may be handed a line of: not locked (those ask
/// for the phone's lock before they open), not archived, with something to
/// type, and holding [query] in the title or text.
List<Note> pickableNotes(List<Note> notes, String query) {
  final needle = query.trim().toLowerCase();
  return [
    for (final note in notes)
      if (!note.locked && !note.archived && !note.isTrashed)
        if (pickLinesOf(note) case final lines
            when lines.isNotEmpty &&
                (needle.isEmpty || lines.any((line) => line.toLowerCase().contains(needle))))
          note,
  ];
}

/// Opened by ZT Keyboard's "Insert from ZT apps" key, once the vault is
/// unlocked: the user taps a note and then the line to type. Pops with that
/// text, or with nothing when the user goes back.
class PickForKeyboardPage extends ConsumerStatefulWidget {
  const PickForKeyboardPage({super.key});

  @override
  ConsumerState<PickForKeyboardPage> createState() => _PickForKeyboardPageState();
}

class _PickForKeyboardPageState extends ConsumerState<PickForKeyboardPage> {
  String _query = '';

  Future<void> _open(Note note) async {
    final lines = pickLinesOf(note);
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(sheet).size.height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              if (lines.length > 1)
                ListTile(
                  leading: const Icon(Icons.notes),
                  title: Text(sheet.l10n.insertWholeNote),
                  onTap: () => Navigator.of(sheet).pop(lines.join('\n')),
                ),
              for (final line in lines)
                ListTile(
                  leading: const Icon(Icons.short_text),
                  title: Text(line, maxLines: 3, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.of(sheet).pop(line),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) Navigator.of(context).pop(picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final notesAsync = ref.watch(notesListProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.insertIntoKeyboard)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l10n.searchNotes,
                helperText: l10n.insertPickHint,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: notesAsync.when(
              data: (all) {
                final notes = pickableNotes(all, _query);
                final hidesLocked = all.any((note) => note.locked && !note.isTrashed);
                if (notes.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        hidesLocked
                            ? '${l10n.insertNoNotes}\n${l10n.insertLockedHidden}'
                            : l10n.insertNoNotes,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: notes.length,
                  itemBuilder: (context, index) {
                    final note = notes[index];
                    final lines = pickLinesOf(note);
                    final hasTitle = note.title.trim().isNotEmpty;
                    final rest = lines.skip(hasTitle ? 1 : 0).join(' ');
                    return ListTile(
                      title: Text(
                        hasTitle ? lines.first : l10n.untitled,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: rest.isEmpty
                          ? null
                          : Text(rest, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => _open(note),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text(l10n.failedNotes('$error'))),
            ),
          ),
        ],
      ),
    );
  }
}
