import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/app_spacing.dart';
import '../application/notebooks_controller.dart';
import '../domain/notebook.dart';

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
      label: 'Notebook: ${name ?? 'None'}',
      hint: 'Opens notebook picker',
      child: ActionChip(
        avatar: const Icon(Icons.folder_outlined, size: 18),
        label: Text(name ?? 'No notebook'),
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
          if (result == null) return;
          onChanged(identical(result, _explicitNone) ? null : result as String);
        },
      ),
    );
  }
}

const _explicitNone = Object();

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
        title: const Text('Rename notebook'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || newName.isEmpty) return;
    final repository = ref.read(notebooksRepositoryProvider);
    await repository?.rename(notebook.id, newName);
  }

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
            Semantics(header: true, child: const Text('Notebook', style: TextStyle(fontWeight: FontWeight.bold))),
            const SizedBox(height: AppSpacing.sm),
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('No notebook'),
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
                    return ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(notebook.name),
                      selected: widget.selectedId == notebook.id,
                      onTap: () => Navigator.of(context).pop<Object?>(notebook.id),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Rename notebook',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _rename(notebook),
                          ),
                          IconButton(
                            tooltip: 'Delete notebook',
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
                  child: Text('Failed to load notebooks: $error'),
                ),
              ),
            ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newNotebookController,
                    decoration: const InputDecoration(hintText: 'New notebook name'),
                    onSubmitted: (_) => _createNotebook(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                IconButton(
                  tooltip: 'Create notebook',
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
