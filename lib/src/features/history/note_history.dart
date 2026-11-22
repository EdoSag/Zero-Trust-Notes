import 'package:uuid/uuid.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../../shared/watch_store.dart';
import '../notes/domain/checklist_item.dart';
import '../notes/domain/note.dart';

/// An earlier text of a note (N-2): its title and text (or checklist) as
/// they were at [savedAt]. Stored as an item of kind `noteVersion` in the
/// account's encrypted store, so history syncs to every device like the
/// notes do, and older Notes builds skip it like any other kind.
class NoteVersion {
  const NoteVersion({
    required this.id,
    required this.noteId,
    required this.title,
    required this.body,
    required this.savedAt,
    required this.recordedAt,
    this.checklist,
  });

  factory NoteVersion.fromItem(LocalItem item) {
    final json = item.json ?? const {};
    final checklist = json['checklist'];
    return NoteVersion(
      id: item.itemId,
      noteId: (json['noteId'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      savedAt: DateTime.tryParse((json['savedAt'] as String?) ?? '') ?? item.updatedAt,
      recordedAt: DateTime.tryParse((json['recordedAt'] as String?) ?? '') ?? item.updatedAt,
      checklist: checklist is List
          ? [
              for (final entry in checklist)
                if (entry is Map) ChecklistItem.fromJson(entry.cast<String, Object?>()),
            ]
          : null,
    );
  }

  static const kind = 'noteVersion';

  static bool isVersionJson(Map<String, Object?>? json) => json?['kind'] == kind;

  final String id;
  final String noteId;
  final String title;
  final String body;
  final List<ChecklistItem>? checklist;

  /// When the note had this text (its last edit before it changed).
  final DateTime savedAt;

  /// When this copy was kept.
  final DateTime recordedAt;

  Map<String, Object?> toItemJson() => {
    'kind': kind,
    'noteId': noteId,
    'title': title,
    'body': body,
    if (checklist != null) 'checklist': [for (final item in checklist!) item.toJson()],
    'savedAt': savedAt.toUtc().toIso8601String(),
    'recordedAt': recordedAt.toUtc().toIso8601String(),
  };
}

/// Keeps earlier versions of the account's own notes.
///
/// Before a note's title or text changes, the text it had is kept, at most
/// once per [sessionGap], so one editing session (which saves after every
/// pause in typing) makes one version, not hundreds. The newest
/// [maxPerNote] versions of each note are kept. The history of a note
/// deleted for good goes the next time the notes load
/// ([forgetDeleted]). Shared notes have none yet.
class NoteHistory {
  NoteHistory({required this._store, required this._sync, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final ZtLocalStore _store;
  final Future<SyncController> Function() _sync;
  final DateTime Function() _clock;
  static const _uuid = Uuid();

  static const sessionGap = Duration(minutes: 10);
  static const maxPerNote = 30;

  /// Note id -> when its last version was kept (read from the store once).
  Map<String, DateTime>? _lastRecorded;

  Future<List<NoteVersion>> _all() async => [
    for (final item in await _store.liveItems())
      if (NoteVersion.isVersionJson(item.json)) NoteVersion.fromItem(item),
  ];

  /// The versions of note [noteId], newest first, and again after every
  /// change.
  Stream<List<NoteVersion>> watch(String noteId) => watchStore(_store, () => versionsOf(noteId));

  Future<List<NoteVersion>> versionsOf(String noteId) async =>
      [
        for (final v in await _all())
          if (v.noteId == noteId) v,
      ]..sort((a, b) => b.savedAt.compareTo(a.savedAt));

  /// Called by the editor before [updated] is saved over [previous] (the
  /// note as stored): keeps [previous]'s text as a version when the text
  /// changes and no version was kept in the last [sessionGap]. Never
  /// throws: history must not stop a save.
  Future<void> beforeSave(Note updated, {required Note? previous}) async {
    try {
      if (previous == null || previous.isShared) return;
      if (previous.title == updated.title && previous.body == updated.body) return;
      if (previous.title.trim().isEmpty && previous.body.trim().isEmpty) return;
      final last = (await _lastRecordedMap())[previous.id];
      if (last != null && _clock().difference(last) < sessionGap) return;
      await keep(previous);
    } on Object {
      // Locked or the store is busy: no version this time.
    }
  }

  /// Keeps [note]'s current text as a version now (before a restore).
  Future<void> keep(Note note) async {
    final now = _clock().toUtc();
    final version = NoteVersion(
      id: _uuid.v4(),
      noteId: note.id,
      title: note.title,
      body: note.body,
      checklist: note.checklist,
      savedAt: note.updatedAt,
      recordedAt: now,
    );
    final sync = await _sync();
    await sync.save(version.id, version.toItemJson());
    (await _lastRecordedMap())[note.id] = now;
    final versions = await versionsOf(note.id);
    for (final old in versions.skip(maxPerNote)) {
      await sync.delete(old.id);
    }
  }

  /// Deletes the history of notes that are gone for good: every version
  /// whose note isn't in [noteIds] (all notes, Trash included). Run once
  /// the notes are loaded. Returns how many versions went.
  Future<int> forgetDeleted(Set<String> noteIds) async {
    try {
      final orphans = [
        for (final v in await _all())
          if (!noteIds.contains(v.noteId)) v,
      ];
      if (orphans.isEmpty) return 0;
      final sync = await _sync();
      for (final v in orphans) {
        await sync.delete(v.id);
      }
      _lastRecorded?.removeWhere((id, _) => !noteIds.contains(id));
      return orphans.length;
    } on Object {
      return 0; // Tried again next time.
    }
  }

  Future<Map<String, DateTime>> _lastRecordedMap() async {
    final known = _lastRecorded;
    if (known != null) return known;
    final map = <String, DateTime>{};
    for (final v in await _all()) {
      final at = map[v.noteId];
      if (at == null || v.recordedAt.isAfter(at)) map[v.noteId] = v.recordedAt;
    }
    return _lastRecorded = map;
  }
}
