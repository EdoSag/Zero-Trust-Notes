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
    );
  }

  final String id;
  final String? notebookId;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;

  Note copyWith({String? title, String? body}) {
    return Note(
      id: id,
      notebookId: notebookId,
      title: title ?? this.title,
      body: body ?? this.body,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// The item JSON every Notes version reads and writes.
  static Map<String, Object?> itemJson({
    required String title,
    required String body,
    String? notebookId,
    required DateTime createdAt,
  }) => {
    'title': title,
    'body': body,
    'notebookId': notebookId,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  Map<String, Object?> toItemJson() =>
      itemJson(title: title, body: body, notebookId: notebookId, createdAt: createdAt);
}
