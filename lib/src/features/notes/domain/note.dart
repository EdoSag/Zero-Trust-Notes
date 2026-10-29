/// Decrypted, in-memory note. Never persisted in this shape — the
/// repository encrypts title/body before every write and decrypts on read.
class Note {
  const Note({
    required this.id,
    required this.notebookId,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String? notebookId;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;

  static const _unset = Object();

  /// [notebookId] defaults to "leave unchanged" rather than "clear" — pass
  /// an explicit `String?` (including `null`, to unfile the note) to change
  /// it, since the field is itself nullable and needs a way to distinguish
  /// "no change" from "set to null".
  Note copyWith({String? title, String? body, Object? notebookId = _unset}) {
    return Note(
      id: id,
      notebookId: identical(notebookId, _unset) ? this.notebookId : notebookId as String?,
      title: title ?? this.title,
      body: body ?? this.body,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
