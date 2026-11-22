import '../notes/domain/note.dart';

/// Links between notes (N-4): `[[Note title]]` anywhere in a note's text,
/// the way Obsidian, Logseq and Standard Notes write them. They are plain
/// text, so older Notes builds, exports and other apps still show them.
abstract final class NoteLinks {
  static final pattern = RegExp(r'\[\[([^\[\]\n]{1,200})\]\]');

  /// URL scheme of a link in the Markdown preview.
  static const scheme = 'ztnote';

  /// The titles [body] links to, in order, each once.
  static List<String> titles(String body) {
    final seen = <String>{};
    return [
      for (final m in pattern.allMatches(body))
        if (_clean(m.group(1)!) case final t when t.isNotEmpty && seen.add(_key(t))) t,
    ];
  }

  /// The note called [title] (any case), not in Trash; the most recently
  /// edited when several share the title. Null when there is none.
  static Note? resolve(String title, Iterable<Note> notes, {String? exceptId}) {
    final key = _key(title);
    Note? best;
    for (final note in notes) {
      if (note.isTrashed || note.id == exceptId || _key(note.title) != key) continue;
      if (best == null || note.updatedAt.isAfter(best.updatedAt)) best = note;
    }
    return best;
  }

  /// Notes (not in Trash) that link to a note titled [title].
  static List<Note> backlinks(String title, String? noteId, Iterable<Note> notes) {
    final key = _key(title);
    if (key.isEmpty) return const [];
    return [
      for (final note in notes)
        if (!note.isTrashed && note.id != noteId && titles(note.body).any((t) => _key(t) == key))
          note,
    ];
  }

  /// [body] with each `[[Title]]` as a Markdown link the preview can open.
  static String toMarkdown(String body) => body.replaceAllMapped(pattern, (m) {
    final title = _clean(m.group(1)!);
    if (title.isEmpty) return m.group(0)!;
    return '[$title]($scheme:${Uri.encodeComponent(title)})';
  });

  /// The title a preview link points to, or null for any other link.
  static String? titleOfHref(String? href) {
    if (href == null || !href.startsWith('$scheme:')) return null;
    return Uri.decodeComponent(href.substring(scheme.length + 1));
  }

  /// [body] with links to [from] pointing to [to] instead (any case).
  static String renamed(String body, String from, String to) {
    final key = _key(from);
    return body.replaceAllMapped(
      pattern,
      (m) => _key(m.group(1)!) == key ? '[[${_clean(to)}]]' : m.group(0)!,
    );
  }

  /// [note] with its links to [from] pointing to [to]; null when it has
  /// none. A checklist's items change with its text.
  static Note? withRenamedLinks(Note note, String from, String to) {
    final body = renamed(note.body, from, to);
    if (body == note.body) return null;
    final checklist = note.checklist;
    if (checklist == null) return note.copyWith(body: body);
    return note.withChecklist([
      for (final item in checklist) item.copyWith(text: renamed(item.text, from, to)),
    ]);
  }

  /// `[[title]]`, for inserting a link.
  static String linkTo(String title) => '[[${_clean(title)}]]';

  static String _clean(String title) =>
      title.replaceAll(RegExp(r'[\[\]\n]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _key(String title) => _clean(title).toLowerCase();
}

