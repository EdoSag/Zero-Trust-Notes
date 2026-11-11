import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zt_sharing_ui/zt_sharing_ui.dart';

import '../../../shared/theme/app_spacing.dart';
import '../../sharing/shared_notebooks.dart';
import '../../sharing/sharing_flows.dart';
import '../application/notebooks_controller.dart';
import '../domain/notebook.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';

/// Compact chip shown in the note editor for the note's current notebook.
/// Tapping opens [_NotebookManagerSheet] to reassign, create, rename, or
/// delete notebooks — there's no separate notebook-management screen, this
/// sheet is the one place all of that happens.
class NotebookField extends ConsumerWidget {
  const NotebookField({super.key, required this.notebookId, required this.onChanged});

  final String? notebookId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notebooksAsync = ref.watch(notebooksListProvider);
    final name = notebooksAsync.maybeWhen(
      data: (notebooks) {
        for (final notebook in notebooks) {
          if (notebook.id == notebookId) return notebook.name;
        }
        return null;
      },
      orElse: () => null,
    );

    return Semantics(
      button: true,
      label: context.l10n.semNotebook(name ?? context.l10n.none),
      hint: context.l10n.opensNotebookPicker,
      child: ActionChip(
        avatar: const Icon(Icons.folder_outlined, size: 18),
        label: Text(name ?? context.l10n.noNotebook),
        onPressed: () async {
          final result = await showModalBottomSheet<Object?>(
            context: context,
            isScrollControlled: true,
            builder: (_) => _NotebookManagerSheet(selectedId: notebookId),
          );
          // A `null` result means the sheet was dismissed (barrier tap/swipe)
          // without an explicit choice — leave the assignment unchanged.
          // Explicitly picking "No notebook" pops [_explicitNone] instead,
          // so the two cases stay distinguishable.
          if (result == null || !context.mounted) return;
          if (result is _ShareRequest) {
            final id = await shareNotebookFlow(context, ref, result.notebook);
            // The note being edited moved with its notebook: follow it.
            if (id != null && id != result.notebook.id && notebookId == result.notebook.id) {
              onChanged(id);
            }
            return;
          }
          onChanged(identical(result, _explicitNone) ? null : result as String);
        },
      ),
    );
  }
}

const _explicitNone = Object();

class _ShareRequest {
  const _ShareRequest(this.notebook);
  final Notebook notebook;
}

class _NotebookManagerSheet extends ConsumerStatefulWidget {
  const _NotebookManagerSheet({required this.selectedId});

  final String? selectedId;

  @override
  ConsumerState<_NotebookManagerSheet> createState() => _NotebookManagerSheetState();
}

class _NotebookManagerSheetState extends ConsumerState<_NotebookManagerSheet> {
  final _newNotebookController = TextEditingController();

  @override
  void dispose() {
    _newNotebookController.dispose();
    super.dispose();
  }

  Future<void> _createNotebook() async {
    final name = _newNotebookController.text.trim();
    if (name.isEmpty) return;
    final repository = ref.read(notebooksRepositoryProvider);
    if (repository == null) return;
    final created = await repository.create(name);
    _newNotebookController.clear();
    if (mounted) Navigator.of(context).pop<Object?>(created.id);
  }

  Future<void> _rename(Notebook notebook) async {
    final controller = TextEditingController(text: notebook.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.renameNotebook),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(context.l10n.cancel)),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(context.l10n.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || newName.isEmpty) return;
    if (notebook.shared case final shared?) {
      await ref.read(sharedNotesProvider.notifier).rename(shared.spaceId, newName);
      return;
    }
    final repository = ref.read(notebooksRepositoryProvider);
    await repository?.rename(notebook.id, newName);
  }

  /// Shares the notebook, or shows who it is shared with: closes the sheet
  /// and lets [NotebookField] run it on the editor.
  void _share(Notebook notebook) => Navigator.of(context).pop<Object?>(_ShareRequest(notebook));

  Future<void> _delete(Notebook notebook) async {
    final repository = ref.read(notebooksRepositoryProvider);
    await repository?.delete(notebook.id);
    if (mounted && widget.selectedId == notebook.id) {
      Navigator.of(context).pop<Object?>(_explicitNone);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notebooksAsync = ref.watch(notebooksListProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: Text(context.l10n.notebook, style: TextStyle(fontWeight: FontWeight.bold))),
            const SizedBox(height: AppSpacing.sm),
            ListTile(
              leading: const Icon(Icons.block),
              title: Text(context.l10n.noNotebook),
              selected: widget.selectedId == null,
              onTap: () => Navigator.of(context).pop<Object?>(_explicitNone),
            ),
            Flexible(
              child: notebooksAsync.when(
                data: (notebooks) => ListView.builder(
                  shrinkWrap: true,
                  itemCount: notebooks.length,
                  itemBuilder: (context, index) {
                    final notebook = notebooks[index];
                    final shared = notebook.shared;
                    return ListTile(
                      leading: Icon(
                        shared != null ? Icons.folder_shared_outlined : Icons.folder_outlined,
                      ),
                      title: Text(notebook.name),
                      selected: widget.selectedId == notebook.id,
                      onTap: () => Navigator.of(context).pop<Object?>(notebook.id),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            key: ValueKey('notebook_share_${notebook.id}'),
                            tooltip: shared != null
                                ? ZtSharingStrings.of(context).peopleAndSharing
                                : context.l10n.shareNotebook,
                            icon: Icon(
                              shared != null ? Icons.people_outline : Icons.group_add_outlined,
                            ),
                            onPressed: () => _share(notebook),
                          ),
                          if (shared == null || shared.isAdmin)
                            IconButton(
                              tooltip: context.l10n.renameNotebook,
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _rename(notebook),
                            ),
                          if (shared == null)
                            IconButton(
                              tooltip: context.l10n.deleteNotebook,
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(notebook),
                            ),
                        ],
                      ),
                    );
                  },
                ),
                loading: () => const Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Text(context.l10n.failedNotebooks('$error')),
                ),
              ),
            ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newNotebookController,
                    decoration: InputDecoration(hintText: context.l10n.newNotebookName),
                    onSubmitted: (_) => _createNotebook(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                IconButton(
                  tooltip: context.l10n.createNotebook,
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: _createNotebook,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
