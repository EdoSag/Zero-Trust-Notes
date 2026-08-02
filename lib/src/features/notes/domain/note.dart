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
}
