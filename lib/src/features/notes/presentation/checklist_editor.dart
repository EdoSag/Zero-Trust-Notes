import 'package:flutter/material.dart';

import '../../../shared/text_direction.dart';
import '../domain/checklist_item.dart';

/// Edits a checklist: tick boxes, ticked items drop below the rest, Enter
/// adds the next item.
class ChecklistEditor extends StatefulWidget {
  const ChecklistEditor({
    super.key,
    required this.items,
    required this.onChanged,
    this.readOnly = false,
  });

  final List<ChecklistItem> items;

  /// [typing] is true for text edits (saved after a pause), false for
  /// ticks, adds and removals (saved at once).
  final void Function(List<ChecklistItem> items, {required bool typing}) onChanged;
  final bool readOnly;

  @override
  State<ChecklistEditor> createState() => _ChecklistEditorState();
}

class _ChecklistEditorState extends State<ChecklistEditor> {
  final _controllers = <String, TextEditingController>{};
  final _focusNodes = <String, FocusNode>{};
  bool _showTicked = true;

  late List<ChecklistItem> _items = ChecklistItem.ordered(widget.items);

  @override
  void didUpdateWidget(ChecklistEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.items, widget.items) && !identical(widget.items, _items)) {
      _items = ChecklistItem.ordered(widget.items);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  TextEditingController _controller(ChecklistItem item) => _controllers.putIfAbsent(item.id, () {
    final controller = TextEditingController(text: item.text);
    controller.addListener(() {
      final index = _items.indexWhere((i) => i.id == item.id);
      if (index < 0 || _items[index].text == controller.text) return;
      _items = [..._items]..[index] = _items[index].copyWith(text: controller.text);
      widget.onChanged(_items, typing: true);
    });
    return controller;
  });

  FocusNode _focus(ChecklistItem item) => _focusNodes.putIfAbsent(item.id, FocusNode.new);

  void _emit(List<ChecklistItem> items) {
    setState(() => _items = items);
    widget.onChanged(items, typing: false);
  }

  void _toggle(ChecklistItem item, bool checked) {
    final updated = [
      for (final i in _items) i.id == item.id ? i.copyWith(checked: checked) : i,
    ];
    _emit(ChecklistItem.ordered(updated));
  }

  void _addAfter(ChecklistItem? item) {
    final created = ChecklistItem.create('');
    final updated = [..._items];
    final index = item == null ? -1 : updated.indexWhere((i) => i.id == item.id);
    if (index < 0) {
      // A new item goes at the end of the unticked ones.
      final firstTicked = updated.indexWhere((i) => i.checked);
      updated.insert(firstTicked < 0 ? updated.length : firstTicked, created);
    } else {
      updated.insert(index + 1, created);
    }
    _emit(updated);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus(created).requestFocus();
    });
  }

  void _remove(ChecklistItem item) {
    _emit([..._items]..removeWhere((i) => i.id == item.id));
    _controllers.remove(item.id)?.dispose();
    _focusNodes.remove(item.id)?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final open = _items.where((item) => !item.checked).toList();
    final ticked = _items.where((item) => item.checked).toList();
    return ListView(
      children: [
        for (final item in open) _row(item),
        if (!widget.readOnly)
          ListTile(
            key: const Key('checklist_add_item'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.add),
            title: const Text('List item'),
            onTap: () => _addAfter(null),
          ),
        if (ticked.isNotEmpty) ...[
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(_showTicked ? Icons.expand_less : Icons.expand_more),
            title: Text('${ticked.length} ticked ${ticked.length == 1 ? 'item' : 'items'}'),
            onTap: () => setState(() => _showTicked = !_showTicked),
          ),
          if (_showTicked) for (final item in ticked) _row(item),
        ],
      ],
    );
  }

  Widget _row(ChecklistItem item) {
    final theme = Theme.of(context);
    return Row(
      key: ValueKey('checklist_row_${item.id}'),
      children: [
        Checkbox(
          value: item.checked,
          semanticLabel: item.text.isEmpty ? 'List item' : item.text,
          onChanged: widget.readOnly ? null : (value) => _toggle(item, value ?? false),
        ),
        Expanded(
          child: TextField(
            controller: _controller(item),
            focusNode: _focus(item),
            readOnly: widget.readOnly,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _addAfter(item),
            textDirection: textDirectionOf(item.text),
            style: item.checked
                ? theme.textTheme.bodyLarge?.copyWith(
                    decoration: TextDecoration.lineThrough,
                    color: theme.colorScheme.onSurfaceVariant,
                  )
                : null,
            decoration: const InputDecoration(border: InputBorder.none, isDense: true),
          ),
        ),
        if (!widget.readOnly)
          IconButton(
            tooltip: 'Remove item',
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => _remove(item),
          ),
      ],
    );
  }
}
