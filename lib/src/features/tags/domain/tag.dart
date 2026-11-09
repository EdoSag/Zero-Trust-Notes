import 'package:zero_trust_core/zero_trust_core.dart';

/// A label notes can carry any number of (see `Note.tagIds`). Stored as its
/// own item in the account's local store, beside the notes, and synced like
/// them.
class Tag {
  const Tag({required this.id, required this.name, this.colorHex});

  factory Tag.fromItem(LocalItem item) {
    final json = item.json ?? const {};
    return Tag(
      id: item.itemId,
      name: (json['name'] as String?) ?? '',
      colorHex: json['colorHex'] as String?,
    );
  }

  static const kind = 'tag';

  static bool isTagJson(Map<String, Object?>? json) => json?['kind'] == kind;

  final String id;
  final String name;
  final String? colorHex;

  Map<String, Object?> toItemJson() => {'kind': kind, 'name': name, 'colorHex': colorHex};
}
