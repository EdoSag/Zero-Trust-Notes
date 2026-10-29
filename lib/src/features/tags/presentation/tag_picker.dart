import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/local_note_vault.dart';
import '../../../shared/theme/app_spacing.dart';
import '../application/tags_controller.dart';

List<String> _assignedIdsOrEmpty(AsyncValue<List<String>> value) {
  return value.maybeWhen(data: (ids) => ids, orElse: () => const <String>[]);
}

Color? _parseColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  final normalized = hex.replaceFirst('#', '');
  final value = int.tryParse(normalized.length == 6 ? 'FF$normalized' : normalized, radix: 16);
  return value == null ? null : Color(value);
}

/// Row of tag chips assigned to a note, plus an "add tag" affordance that
/// opens [_TagManagerSheet]. A brand-new, not-yet-persisted note has no
/// [noteId] yet — [ensureNoteId] flushes the pending autosave so tags always
/// attach to a real row before the picker opens.
class TagField extends ConsumerWidget {
  const TagField({super.key, required this.noteId, required this.ensureNoteId});

  final String? noteId;
  final Future<String?> Function() ensureNoteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignedIds = noteId == null
        ? const AsyncValue<List<String>>.data([])
        : ref.watch(noteTagIdsProvider(noteId!));
    final allTagsAsync = ref.watch(tagsListProvider);

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ...assignedIds.maybeWhen(
          data: (ids) => allTagsAsync.maybeWhen(
            data: (allTags) => [
              for (final tag in allTags.where((tag) => ids.contains(tag.id)))
                Chip(
                  label: Text(tag.name),
                  backgroundColor: _parseColor(tag.colorHex),
                  onDeleted: () async {
                    final repository = ref.read(tagsRepositoryProvider);
                    if (repository == null || noteId == null) return;
                    await repository.setTagsForNote(noteId!, ids.toSet()..remove(tag.id));
                  },
                ),
            ],
            orElse: () => const <Widget>[],
          ),
          orElse: () => const <Widget>[],
        ),
        ActionChip(
          avatar: const Icon(Icons.sell_outlined, size: 18),
          label: const Text('Add tag'),
          onPressed: () async {
            final id = noteId ?? await ensureNoteId();
            if (id == null || !context.mounted) return;
            await showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => _TagManagerSheet(noteId: id),
            );
          },
        ),
      ],
    );
  }
}

class _TagManagerSheet extends ConsumerStatefulWidget {
  const _TagManagerSheet({required this.noteId});

  final String noteId;

  @override
  ConsumerState<_TagManagerSheet> createState() => _TagManagerSheetState();
}

class _TagManagerSheetState extends ConsumerState<_TagManagerSheet> {
  final _newTagController = TextEditingController();

  @override
  void dispose() {
    _newTagController.dispose();
    super.dispose();
  }

  Future<void> _toggle(Tag tag, List<String> currentIds, bool selected) async {
    final repository = ref.read(tagsRepositoryProvider);
    if (repository == null) return;
    final next = currentIds.toSet();
    selected ? next.add(tag.id) : next.remove(tag.id);
    await repository.setTagsForNote(widget.noteId, next);
  }

  Future<void> _createTag(List<String> currentIds) async {
    final name = _newTagController.text.trim();
    if (name.isEmpty) return;
    final repository = ref.read(tagsRepositoryProvider);
    if (repository == null) return;
    final created = await repository.create(name);
    await repository.setTagsForNote(widget.noteId, {...currentIds, created.id});
    _newTagController.clear();
  }

  Future<void> _delete(Tag tag) async {
    final repository = ref.read(tagsRepositoryProvider);
    await repository?.delete(tag.id);
  }

  @override
  Widget build(BuildContext context) {
    final allTagsAsync = ref.watch(tagsListProvider);
    final assignedAsync = ref.watch(noteTagIdsProvider(widget.noteId));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: const Text('Tags', style: TextStyle(fontWeight: FontWeight.bold))),
            const SizedBox(height: AppSpacing.sm),
            Flexible(
              child: assignedAsync.when(
                data: (assignedIds) => allTagsAsync.when(
                  data: (allTags) => ListView.builder(
                    shrinkWrap: true,
                    itemCount: allTags.length,
                    itemBuilder: (context, index) {
                      final tag = allTags[index];
                      final selected = assignedIds.contains(tag.id);
                      return CheckboxListTile(
                        value: selected,
                        onChanged: (value) => _toggle(tag, assignedIds, value ?? false),
                        title: Text(tag.name),
                        secondary: IconButton(
                          tooltip: 'Delete tag',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(tag),
                        ),
                      );
                    },
                  ),
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Text('Failed to load tags: $error'),
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Text('Failed to load tags: $error'),
              ),
            ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newTagController,
                    decoration: const InputDecoration(hintText: 'New tag name'),
                    onSubmitted: (_) => _createTag(_assignedIdsOrEmpty(assignedAsync)),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                IconButton(
                  tooltip: 'Create tag',
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => _createTag(_assignedIdsOrEmpty(assignedAsync)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
