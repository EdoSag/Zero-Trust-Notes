import 'package:zero_trust_core/zero_trust_core.dart';

/// A named group of notes. Stored as its own item in the account's local
/// store, beside the notes, and synced like them.
class Notebook {
  const Notebook({required this.id, required this.name});

  factory Notebook.fromItem(LocalItem item) =>
      Notebook(id: item.itemId, name: (item.json?['name'] as String?) ?? '');

  static const kind = 'notebook';

  static bool isNotebookJson(Map<String, Object?>? json) => json?['kind'] == kind;

  final String id;
  final String name;

  Map<String, Object?> toItemJson() => {'kind': kind, 'name': name};
}
