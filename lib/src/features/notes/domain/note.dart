import 'package:zero_trust_core/zero_trust_core.dart';

import 'checklist_item.dart';
import 'note_color.dart';

/// Decrypted, in-memory note. Stored as one item in the account's encrypted
/// local store (see `ZtLocalStore`) and synced as one sealed `vault_items`
/// row.
///
/// Every field added after the first core version (pin, colour, archive,
/// trash, checklist, reminder, images, position, lock) is optional in the item JSON, so notes written
/// by older Notes builds read as plain, unpinned text notes. Keys this build
/// doesn't know are kept in [extra] and written back unchanged, so a newer
/// build's fields survive an edit made here.
class Note {
  const Note({
    required this.id,
    required this.notebookId,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    this.tagIds = const [],
    this.pinned = false,
    this.color = NoteColor.none,
    this.archived = false,
    this.trashedAt,
    this.checklist,
    this.reminderAt,
    this.images = const [],
    this.position,
    this.locked = false,
    this.extra = const {},
  });

  /// A live (not deleted) item from the local store.
  factory Note.fromItem(LocalItem item) {
    final json = item.json ?? const {};
    final checklistJson = json['checklist'];
    return Note(
      id: item.itemId,
      notebookId: json['notebookId'] as String?,
      title: (json['title'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      createdAt: _date(json['createdAt']) ?? item.updatedAt,
      updatedAt: item.updatedAt,
      tagIds: [...?(json['tagIds'] as List?)?.whereType<String>()],
      pinned: json['pinned'] == true,
      color: NoteColor.fromKey(json['color'] as String?),
      archived: json['archived'] == true,
      trashedAt: _date(json['trashedAt']),
      checklist: checklistJson is List
          ? [
              for (final entry in checklistJson)
                if (entry is Map) ChecklistItem.fromJson(entry.cast<String, Object?>()),
            ]
          : null,
      reminderAt: _date(json['reminderAt']),
      images: imagesFromJson(json['images']),
      position: (json['position'] as num?)?.toDouble(),
      locked: json['locked'] == true,
      extra: {
        for (final entry in json.entries)
          if (!_knownKeys.contains(entry.key)) entry.key: entry.value,
      },
    );
  }

  /// The note's image refs; an entry this build can't read is skipped
  /// rather than failing the whole note.
  static List<ZtAttachmentRef> imagesFromJson(Object? value) {
    if (value is! List) return const [];
    final images = <ZtAttachmentRef>[];
    for (final entry in value) {
      if (entry is! Map) continue;
      try {
        images.add(ZtAttachmentRef.fromJson(entry.cast<String, Object?>()));
      } on Object {
        // Malformed or from a newer format: leave it out.
      }
    }
    return images;
  }

  static DateTime? _date(Object? value) => switch (value) {
    final String s => DateTime.tryParse(s),
    _ => null,
  };

  static const _knownKeys = {
    'title',
    'body',
    'notebookId',
    'tagIds',
    'createdAt',
    'pinned',
    'color',
    'archived',
    'trashedAt',
    'checklist',
    'reminderAt',
    'images',
    'position',
    'locked',
  };

  /// Notebooks and tags share the store with notes and carry a `kind`.
  /// Notes never have one, so every Notes version keeps reading them.
  static bool isNoteJson(Map<String, Object?>? json) => json != null && json['kind'] == null;

  /// How long a note stays in Trash before it's deleted for good.
  static const trashRetention = Duration(days: 30);

  final String id;
  final String? notebookId;
  final String title;

  /// The note's text. For a checklist this is the list written as Markdown
  /// task lines (`- [ ] milk`), so search, export, widgets and older Notes
  /// builds all see the items.
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> tagIds;
  final bool pinned;
  final NoteColor color;
  final bool archived;

  /// Set while the note is in Trash.
  final DateTime? trashedAt;

  /// Non-null for a checklist note.
  final List<ChecklistItem>? checklist;
  final DateTime? reminderAt;

  /// Encrypted images (see `ZtAttachments`), in the order they were added.
  /// Each ref holds the image's own key, so it lives only inside this
  /// sealed item.
  final List<ZtAttachmentRef> images;

  /// Where the person dragged the note, as a sort key in the same scale as
  /// [orderKey] (milliseconds). Null for a note never moved by hand.
  final double? position;

  /// Opening it asks for the device's fingerprint, face or screen lock
  /// again, and the list shows only its title.
  final bool locked;
  final Map<String, Object?> extra;

  bool get isTrashed => trashedAt != null;
  bool get isChecklist => checklist != null;
  bool get hasImages => images.isNotEmpty;

  /// Custom order, highest first: a note's dragged [position], or its
  /// last edit for one never moved. New and edited notes come to the top;
  /// a moved note stays where it was put.
  double get orderKey => position ?? updatedAt.millisecondsSinceEpoch.toDouble();

  /// When a trashed note is deleted for good.
  DateTime? get purgeAt => trashedAt?.add(trashRetention);

  static const _unset = Object();

  /// Nullable fields ([notebookId], [trashedAt], [checklist], [reminderAt],
  /// [position])
  /// default to "leave unchanged"; pass `null` explicitly to clear them.
  Note copyWith({
    String? title,
    String? body,
    Object? notebookId = _unset,
    List<String>? tagIds,
    bool? pinned,
    NoteColor? color,
    bool? archived,
    Object? trashedAt = _unset,
    Object? checklist = _unset,
    Object? reminderAt = _unset,
    List<ZtAttachmentRef>? images,
    Object? position = _unset,
    bool? locked,
    DateTime? updatedAt,
  }) {
    return Note(
      id: id,
      notebookId: identical(notebookId, _unset) ? this.notebookId : notebookId as String?,
      title: title ?? this.title,
      body: body ?? this.body,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      tagIds: tagIds ?? this.tagIds,
      pinned: pinned ?? this.pinned,
      color: color ?? this.color,
      archived: archived ?? this.archived,
      trashedAt: identical(trashedAt, _unset) ? this.trashedAt : trashedAt as DateTime?,
      checklist: identical(checklist, _unset) ? this.checklist : checklist as List<ChecklistItem>?,
      reminderAt: identical(reminderAt, _unset) ? this.reminderAt : reminderAt as DateTime?,
      images: images ?? this.images,
      position: identical(position, _unset) ? this.position : position as double?,
      locked: locked ?? this.locked,
      extra: extra,
    );
  }

  /// Turns a text note into a checklist (one item per non-empty line) or a
  /// checklist back into text (one line per item, ticks dropped).
  Note toggledChecklist() {
    if (isChecklist) {
      return copyWith(checklist: null, body: [for (final item in checklist!) item.text].join('\n'));
    }
    final items = ChecklistItem.parseLines(body);
    return copyWith(checklist: items, body: ChecklistItem.toMarkdown(items));
  }

  /// A checklist note with [items], ticked items moved below unticked ones.
  Note withChecklist(List<ChecklistItem> items) {
    final ordered = ChecklistItem.ordered(items);
    return copyWith(checklist: ordered, body: ChecklistItem.toMarkdown(ordered));
  }

  /// The item JSON every Notes version reads and writes.
  static Map<String, Object?> itemJson({
    required String title,
    required String body,
    String? notebookId,
    List<String> tagIds = const [],
    required DateTime createdAt,
    bool pinned = false,
    NoteColor color = NoteColor.none,
    bool archived = false,
    DateTime? trashedAt,
    List<ChecklistItem>? checklist,
    DateTime? reminderAt,
    List<ZtAttachmentRef> images = const [],
    double? position,
    bool locked = false,
    Map<String, Object?> extra = const {},
  }) => {
    ...extra,
    'title': title,
    'body': body,
    'notebookId': notebookId,
    'tagIds': tagIds,
    'createdAt': createdAt.toUtc().toIso8601String(),
    // Only written when set, so plain notes stay byte-for-byte what older
    // builds wrote.
    if (pinned) 'pinned': true,
    if (color != NoteColor.none) 'color': color.key,
    if (archived) 'archived': true,
    if (trashedAt != null) 'trashedAt': trashedAt.toUtc().toIso8601String(),
    if (checklist != null) 'checklist': [for (final item in checklist) item.toJson()],
    if (reminderAt != null) 'reminderAt': reminderAt.toUtc().toIso8601String(),
    if (images.isNotEmpty) 'images': [for (final image in images) image.toJson()],
    'position': ?position,
    if (locked) 'locked': true,
  };

  Map<String, Object?> toItemJson() => itemJson(
    title: title,
    body: body,
    notebookId: notebookId,
    tagIds: tagIds,
    createdAt: createdAt,
    pinned: pinned,
    color: color,
    archived: archived,
    trashedAt: trashedAt,
    checklist: checklist,
    reminderAt: reminderAt,
    images: images,
    position: position,
    locked: locked,
    extra: extra,
  );
}
