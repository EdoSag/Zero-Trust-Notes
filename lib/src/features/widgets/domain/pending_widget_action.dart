/// An action requested by a home-screen widget tap, carried out once the
/// vault is confirmed unlocked. The consumer clears the pending action
/// immediately after acting on it so rebuilds don't replay it.
sealed class PendingWidgetAction {
  const PendingWidgetAction();
}

/// What the quick capture bar's buttons start: a text note, a checklist,
/// a voice note, or a photo.
enum NewNoteKind {
  text,
  checklist,
  voice,
  photo;

  /// From the widget's `zerotrustnotes://new-note?kind=…`; text if missing
  /// or unknown.
  static NewNoteKind parse(String? value) =>
      values.where((kind) => kind.name == value).firstOrNull ?? text;
}

class OpenNewNote extends PendingWidgetAction {
  const OpenNewNote([this.kind = NewNoteKind.text]);

  final NewNoteKind kind;
}

/// Today's note (N-5), from the app icon shortcut.
class OpenDailyNote extends PendingWidgetAction {
  const OpenDailyNote();
}

class OpenNote extends PendingWidgetAction {
  const OpenNote(this.noteId);

  final String noteId;
}

/// [appWidgetId] is Android's widget instance id, carried as a string
/// throughout the Dart layer since it only ever needs to round-trip back to
/// `home_widget`'s string-keyed storage.
class ConfigureNoteWidget extends PendingWidgetAction {
  const ConfigureNoteWidget(this.appWidgetId, {this.checklist = false});

  final String appWidgetId;

  /// A Checklist widget (W5): only checklist notes can be picked.
  final bool checklist;
}

/// ZT Keyboard's "Insert from ZT apps" key opened Notes: the user picks a
/// line of a note for the keyboard to type, after unlock.
class PickTextForKeyboard extends PendingWidgetAction {
  const PickTextForKeyboard();
}

/// Text, images and files shared to Notes from another app: opens a new note with
/// them, after unlock if needed.
class CreateNoteFromShare extends PendingWidgetAction {
  const CreateNoteFromShare(this.content);

  final SharedContent content;
}

/// What another app shared. [images] and [files] are plain copies on this
/// device until the new note encrypts them; whoever consumes them deletes
/// them.
class SharedContent {
  const SharedContent({
    this.text,
    this.subject,
    this.images = const [],
    this.files = const [],
    this.skipped = 0,
  });

  factory SharedContent.fromMap(Map<Object?, Object?> map) => SharedContent(
    text: map['text'] as String?,
    subject: map['subject'] as String?,
    images: _files(map['images']),
    files: _files(map['files']),
    skipped: (map['skipped'] as int?) ?? 0,
  );

  static List<SharedImageFile> _files(Object? list) => [
    for (final file in list is List ? list : const [])
      if (file is Map && file['path'] is String)
        SharedImageFile(
          path: file['path'] as String,
          mimeType: file['mimeType'] as String?,
          name: file['name'] as String?,
        ),
  ];

  final String? text;
  final String? subject;
  final List<SharedImageFile> images;

  /// Anything that isn't a picture: PDFs, documents (N-7).
  final List<SharedImageFile> files;

  /// Items that couldn't be taken (too large, unreadable, too many).
  final int skipped;

  /// The note's title: the subject apps like browsers send with a link,
  /// unless it just repeats the text.
  String get title {
    final subject = this.subject?.trim() ?? '';
    return subject == text?.trim() ? '' : subject;
  }

  String get body => text?.trim() ?? '';
}

/// A shared image or file, as a plain copy in the app's cache.
class SharedImageFile {
  const SharedImageFile({required this.path, this.mimeType, this.name});

  final String path;
  final String? mimeType;
  final String? name;
}
