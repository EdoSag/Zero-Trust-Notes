import 'package:intl/intl.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';

import '../notes/domain/checklist_item.dart';
import '../notes/domain/note.dart';

/// A note to start from (N-5): a title, text or checklist items, with
/// placeholders filled in when it is used. The person's own templates are
/// items of kind `template` in the account's store, beside notes and
/// notebooks, so they sync to every device; Notes versions without
/// templates skip them like any other kind. A few built-in ones are always
/// offered and never stored.
class NoteTemplate {
  const NoteTemplate({
    required this.id,
    required this.name,
    this.title = '',
    this.body = '',
    this.checklist,
    this.daily = false,
    this.builtIn = false,
  });

  factory NoteTemplate.fromItem(LocalItem item) {
    final json = item.json ?? const {};
    final checklist = json['checklist'];
    return NoteTemplate(
      id: item.itemId,
      name: (json['name'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      checklist: checklist is List
          ? [
              for (final entry in checklist)
                if (entry is Map) ChecklistItem.fromJson(entry.cast<String, Object?>()),
            ]
          : null,
      daily: json['daily'] == true,
    );
  }

  /// A template made from [note]: its title, text or checklist (ticks
  /// cleared).
  factory NoteTemplate.fromNote(Note note, {required String id, required String name}) =>
      NoteTemplate(
        id: id,
        name: name,
        title: note.title,
        body: note.isChecklist ? '' : note.body,
        checklist: note.checklist == null
            ? null
            : [for (final item in note.checklist!) item.copyWith(checked: false)],
      );

  static const kind = 'template';

  static bool isTemplateJson(Map<String, Object?>? json) => json?['kind'] == kind;

  final String id;
  final String name;
  final String title;
  final String body;
  final List<ChecklistItem>? checklist;

  /// The template a new daily note starts from. At most one.
  final bool daily;

  /// Offered by the app, not stored; can't be renamed or deleted.
  final bool builtIn;

  bool get isChecklist => checklist != null;

  NoteTemplate copyWith({String? name, bool? daily}) => NoteTemplate(
    id: id,
    name: name ?? this.name,
    title: title,
    body: body,
    checklist: checklist,
    daily: daily ?? this.daily,
    builtIn: builtIn,
  );

  Map<String, Object?> toItemJson() => {
    'kind': kind,
    'name': name,
    'title': title,
    'body': body,
    if (checklist != null) 'checklist': [for (final item in checklist!) item.toJson()],
    if (daily) 'daily': true,
  };

  /// The title, text and checklist of a new note from this template, with
  /// `{{date}}` (2026-11-22), `{{longdate}}` (in [localeName]'s words),
  /// `{{weekday}}` and `{{time}}` filled in for [now].
  ({String title, String body, List<ChecklistItem>? checklist}) fill(
    DateTime now, {
    required String localeName,
  }) {
    // The app loads date names for its languages; anything else falls
    // back to English rather than failing the note.
    String format(DateFormat Function(String? locale) pattern) {
      try {
        return pattern(localeName).format(now);
      } on Object {
        return pattern(null).format(now);
      }
    }

    String expand(String text) => text.replaceAllMapped(_placeholder, (m) {
      return switch (m.group(1)!.toLowerCase()) {
        'date' => isoDate(now),
        'longdate' => format(DateFormat.yMMMMEEEEd),
        'weekday' => format(DateFormat.EEEE),
        'time' => format(DateFormat.Hm),
        _ => m.group(0)!,
      };
    });
    return (
      title: expand(title),
      body: expand(body),
      checklist: checklist == null
          ? null
          : [for (final item in checklist!) ChecklistItem.create(expand(item.text))],
    );
  }

  static final _placeholder = RegExp(r'\{\{\s*(date|longdate|weekday|time)\s*\}\}', caseSensitive: false);

  /// 2026-11-22: the title of that day's daily note.
  static String isoDate(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  /// The templates the app offers to everyone, in [l]'s language.
  static List<NoteTemplate> builtIns(AppL10n l) => [
    NoteTemplate(
      id: 'builtin:journal',
      name: l.templateJournal,
      title: '{{date}}',
      body: l.templateJournalBody('{{longdate}}'),
      builtIn: true,
    ),
    NoteTemplate(
      id: 'builtin:meeting',
      name: l.templateMeeting,
      title: l.templateMeetingTitle('{{date}}'),
      body: l.templateMeetingBody,
      builtIn: true,
    ),
    NoteTemplate(
      id: 'builtin:todo',
      name: l.templateTodo,
      title: l.templateTodoTitle('{{date}}'),
      checklist: [
        for (final line in l.templateTodoItems.split('\n'))
          if (line.trim().isNotEmpty) ChecklistItem(id: 'builtin', text: line.trim()),
      ],
      builtIn: true,
    ),
  ];
}
