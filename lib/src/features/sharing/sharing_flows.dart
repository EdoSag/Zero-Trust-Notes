import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zt_sharing_ui/zt_sharing_ui.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';

import '../notebooks/domain/notebook.dart';
import '../notes/application/notes_providers.dart';
import '../notes/domain/note.dart';
import 'shared_notebooks.dart';

void _snack(BuildContext context, String text) => ScaffoldMessenger.maybeOf(context)
  ?..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 4)));

/// The name a shared space shows: the notebook's, or for a note shared on
/// its own, the note's title.
String sharedSpaceTitle(BuildContext context, Notebook? notebook) {
  final name = notebook?.name.trim() ?? '';
  return name.isEmpty ? context.l10n.untitled : name;
}

/// People, invites, leaving and deleting for one shared space.
Future<void> openSharedSpace(
  BuildContext context,
  WidgetRef ref,
  String spaceId, {
  bool inviteNow = false,
}) {
  final notebook = ref.read(sharedNotesProvider).bySpace(spaceId);
  return ZtSpacePage.open(
    context,
    spaceId: spaceId,
    title: sharedSpaceTitle(context, notebook),
    description: context.l10n.sharedNotebookDescription,
    inviteNow: inviteNow,
  );
}

/// Joins a shared notebook or note from an invite link.
Future<void> openJoinShared(BuildContext context, WidgetRef ref) async {
  final started = await ZtJoinSpacePage.open(context);
  if (started != null) await ref.read(sharedNotesProvider.notifier).reload();
}

bool _canShare(BuildContext context, WidgetRef ref) {
  if (ref.read(sharedNotesProvider).available && ref.read(notesRepositoryProvider) != null) {
    return true;
  }
  _snack(context, context.l10n.sharingUnavailable);
  return false;
}

Future<bool> _explain(BuildContext context, String title, String body) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.l10n.cancel)),
        TextButton(
          key: const Key('share_continue'),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ZtSharingStrings.of(context).continueLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Shares [notebook] (or, if it already is shared, shows who it is shared
/// with). Moves its notes into the shared notebook, then opens the invite.
/// Returns the shared notebook's id, or null when cancelled.
Future<String?> shareNotebookFlow(BuildContext context, WidgetRef ref, Notebook notebook) async {
  final shared = notebook.shared;
  if (shared != null) {
    await openSharedSpace(context, ref, shared.spaceId);
    return notebook.id;
  }
  if (!_canShare(context, ref)) return null;
  final title = context.l10n.shareNamed(notebook.name);
  if (!await _explain(context, title, context.l10n.shareNotebookExplain)) return null;
  if (!context.mounted) return null;
  final myName = await ztAskSharingName(context, ref, title: title);
  if (myName == null || !context.mounted) return null;
  final String spaceId;
  try {
    spaceId = await ref
        .read(notesRepositoryProvider)!
        .shareNotebook(ref.read(sharedNotesProvider.notifier), notebook, myName: myName);
  } on Object {
    if (context.mounted) _snack(context, context.l10n.sharingUnavailable);
    return null;
  }
  if (context.mounted) await openSharedSpace(context, ref, spaceId, inviteNow: true);
  return Notebook.sharedId(spaceId);
}

/// Shares one note on its own (or shows who it is shared with). Returns
/// the note as now stored, or null when nothing changed.
Future<Note?> shareNoteFlow(BuildContext context, WidgetRef ref, Note note) async {
  final spaceId = note.spaceId;
  if (spaceId != null) {
    await openSharedSpace(context, ref, spaceId);
    return null;
  }
  if (note.locked) {
    _snack(context, context.l10n.lockedCantBeShared);
    return null;
  }
  if (!_canShare(context, ref)) return null;
  final name = note.title.trim().isEmpty ? context.l10n.untitled : note.title.trim();
  final title = context.l10n.shareNamed(name);
  if (!await _explain(context, title, context.l10n.shareNoteExplain)) return null;
  if (!context.mounted) return null;
  final myName = await ztAskSharingName(context, ref, title: title);
  if (myName == null || !context.mounted) return null;
  final String newSpace;
  try {
    newSpace = await ref
        .read(notesRepositoryProvider)!
        .shareNote(ref.read(sharedNotesProvider.notifier), note, myName: myName, name: name);
  } on Object {
    if (context.mounted) _snack(context, context.l10n.sharingUnavailable);
    return null;
  }
  if (context.mounted) await openSharedSpace(context, ref, newSpace, inviteNow: true);
  return note.located(newSpace, notebookId: null);
}

/// People waiting to join anything this account shares, for the top of the
/// notes list.
class SharedJoinRequests extends ConsumerWidget {
  const SharedJoinRequests({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notebooks = ref.watch(sharedNotesProvider.select((s) => s.notebooks));
    if (!notebooks.any((n) => n.shared!.isAdmin)) return const SizedBox.shrink();
    return ZtJoinRequestCards(
      titleOf: (spaceId) =>
          sharedSpaceTitle(context, ref.read(sharedNotesProvider).bySpace(spaceId)),
    );
  }
}
