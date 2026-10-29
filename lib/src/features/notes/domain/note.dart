import 'package:zero_trust_core/zero_trust_core.dart';

/// Decrypted, in-memory note. Stored as one item in the account's encrypted
/// local store (see `ZtLocalStore`) and synced as one sealed `vault_items`
/// row.
class Note {
  const Note({
    required this.id,
    required this.notebookId,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    this.tagIds = const [],
  });

  /// A live (not deleted) item from the local store.
  factory Note.fromItem(LocalItem item) {
    final json = item.json ?? const {};
    return Note(
      id: item.itemId,
      notebookId: json['notebookId'] as String?,
      title: (json['title'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      createdAt: switch (json['createdAt']) {
        final String s => DateTime.parse(s),
        _ => item.updatedAt,
      },
      updatedAt: item.updatedAt,
      tagIds: [...?(json['tagIds'] as List?)?.whereType<String>()],
    );
  }

  /// Notebooks and tags share the store with notes and carry a `kind`.
  /// Notes never have one, so every Notes version keeps reading them.
  static bool isNoteJson(Map<String, Object?>? json) => json != null && json['kind'] == null;

  final String id;
  final String? notebookId;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> tagIds;

  static const _unset = Object();

  /// [notebookId] defaults to "leave unchanged" rather than "clear" — pass
  /// an explicit `String?` (including `null`, to unfile the note) to change
  /// it, since the field is itself nullable and needs a way to distinguish
  /// "no change" from "set to null".
  Note copyWith({
    String? title,
    String? body,
    Object? notebookId = _unset,
    List<String>? tagIds,
  }) {
    return Note(
      id: id,
      notebookId: identical(notebookId, _unset) ? this.notebookId : notebookId as String?,
      title: title ?? this.title,
      body: body ?? this.body,
      createdAt: createdAt,
      updatedAt: updatedAt,
      tagIds: tagIds ?? this.tagIds,
    );
  }

  /// The item JSON every Notes version reads and writes.
  static Map<String, Object?> itemJson({
    required String title,
    required String body,
    String? notebookId,
    List<String> tagIds = const [],
    required DateTime createdAt,
  }) => {
    'title': title,
    'body': body,
    'notebookId': notebookId,
    'tagIds': tagIds,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  Map<String, Object?> toItemJson() => itemJson(
    title: title,
    body: body,
    notebookId: notebookId,
    tagIds: tagIds,
    createdAt: createdAt,
  );
}
