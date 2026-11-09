import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/app_spacing.dart';
import '../application/tags_controller.dart';
import '../domain/tag.dart';

Color? _parseColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  final normalized = hex.replaceFirst('#', '');
  final value = int.tryParse(normalized.length == 6 ? 'FF$normalized' : normalized, radix: 16);
  return value == null ? null : Color(value);
}

/// Row of tag chips assigned to a note, plus an "add tag" affordance that
/// opens [_TagManagerSheet]. The editor owns [tagIds] (they're saved with
/// the note) and gets every change through [onChanged].
class TagField extends ConsumerWidget {
  const TagField({super.key, required this.tagIds, required this.onChanged});

  final List<String> tagIds;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allTagsAsync = ref.watch(tagsListProvider);

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Ids of tags deleted elsewhere simply don't render.
        ...allTagsAsync.maybeWhen(
          data: (allTags) => [
            for (final tag in allTags.where((tag) => tagIds.contains(tag.id)))
              Chip(
                label: Text(tag.name),
                backgroundColor: _parseColor(tag.colorHex),
                onDeleted: () => onChanged([...tagIds]..remove(tag.id)),
              ),
          ],
          orElse: () => const <Widget>[],
        ),
        ActionChip(
          avatar: const Icon(Icons.sell_outlined, size: 18),
          label: const Text('Add tag'),
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => _TagManagerSheet(initialIds: tagIds, onChanged: onChanged),
          ),
        ),
      ],
    );
  }
}

class _TagManagerSheet extends ConsumerStatefulWidget {
  const _TagManagerSheet({required this.initialIds, required this.onChanged});

  final List<String> initialIds;
  final ValueChanged<List<String>> onChanged;

  @override
  ConsumerState<_TagManagerSheet> createState() => _TagManagerSheetState();
}

class _TagManagerSheetState extends ConsumerState<_TagManagerSheet> {
  final _newTagController = TextEditingController();
  late List<String> _selected = [...widget.initialIds];

  @override
  void dispose() {
    _newTagController.dispose();
    super.dispose();
  }

  void _setSelected(List<String> next) {
    setState(() => _selected = next);
    widget.onChanged(next);
  }

  void _toggle(Tag tag, bool selected) {
    _setSelected(selected ? [..._selected, tag.id] : ([..._selected]..remove(tag.id)));
  }

  Future<void> _createTag() async {
    final name = _newTagController.text.trim();
    if (name.isEmpty) return;
    final repository = ref.read(tagsRepositoryProvider);
    if (repository == null) return;
    final created = await repository.create(name);
    _newTagController.clear();
    if (mounted) _setSelected([..._selected, created.id]);
  }

  Future<void> _delete(Tag tag) async {
    final repository = ref.read(tagsRepositoryProvider);
    await repository?.delete(tag.id);
    if (mounted && _selected.contains(tag.id)) _setSelected([..._selected]..remove(tag.id));
  }

  @override
  Widget build(BuildContext context) {
    final allTagsAsync = ref.watch(tagsListProvider);

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
              child: allTagsAsync.when(
                data: (allTags) => ListView.builder(
                  shrinkWrap: true,
                  itemCount: allTags.length,
                  itemBuilder: (context, index) {
                    final tag = allTags[index];
                    final selected = _selected.contains(tag.id);
                    return CheckboxListTile(
                      value: selected,
                      onChanged: (value) => _toggle(tag, value ?? false),
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
            ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newTagController,
                    decoration: const InputDecoration(hintText: 'New tag name'),
                    onSubmitted: (_) => _createTag(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                IconButton(
                  tooltip: 'Create tag',
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: _createTag,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
