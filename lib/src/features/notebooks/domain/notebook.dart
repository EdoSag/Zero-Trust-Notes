import 'package:zero_trust_core/zero_trust_core.dart';

/// A named group of notes. Stored as its own item in the account's local
/// store, beside the notes, and synced like them. A shared notebook lives in
/// its own shared space instead (see [shared]).
class Notebook {
  const Notebook({required this.id, required this.name, this.shared});

  factory Notebook.fromItem(LocalItem item) =>
      Notebook(id: item.itemId, name: (item.json?['name'] as String?) ?? '');

  static const kind = 'notebook';

  static bool isNotebookJson(Map<String, Object?>? json) => json?['kind'] == kind;

  final String id;
  final String name;

  /// Set for a notebook shared with other Zero-Trust users. Never stored:
  /// it comes from the space each time it is read.
  final SharedNotebookInfo? shared;

  bool get isShared => shared != null;

  Map<String, Object?> toItemJson() => {'kind': kind, 'name': name};

  /// The notebook id of the shared notebook kept in space [spaceId].
  static String sharedId(String spaceId) => '$sharedPrefix$spaceId';
  static const sharedPrefix = 'space:';

  /// The space of a shared notebook's id, or null for the account's own
  /// notebooks (and for no notebook).
  static String? spaceIdOf(String? notebookId) =>
      notebookId != null && notebookId.startsWith(sharedPrefix)
      ? notebookId.substring(sharedPrefix.length)
      : null;
}

/// What this phone knows about one shared space of Notes: a shared notebook,
/// or a note shared on its own ([single]).
class SharedNotebookInfo {
  const SharedNotebookInfo({
    required this.spaceId,
    required this.isAdmin,
    this.single = false,
    this.waiting = false,
    this.members = const [],
  });

  final String spaceId;

  /// This account is an owner: it can rename, invite and remove people.
  final bool isAdmin;

  /// A note shared on its own rather than a notebook: its note shows in
  /// the main list, not under a notebook.
  final bool single;

  /// Joined but not let in yet (or not synced yet): nothing to show.
  final bool waiting;
  final List<SpaceMember> members;
}
