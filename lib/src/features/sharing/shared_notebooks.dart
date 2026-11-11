import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../notebooks/domain/notebook.dart';
import '../notes/application/notes_providers.dart';
import '../notes/domain/note.dart';

/// Shared notes (N18), on core Z24 shared spaces. A notebook shared with
/// other Zero-Trust users, or one note shared on its own, lives in its own
/// space: the item [notebookItemId] (kind `notebook`) names it, and every
/// other item without a kind is a note, exactly like in the account's own
/// store. Everything in a space is end-to-end encrypted with the space's
/// key, which only members hold; the server sees member ids and sealed
/// blobs, never names or notes.
///
/// Only owners (space admins) rename it; every member adds, edits and
/// deletes notes.
const SpacePolicy notesSpacePolicy = SpacePolicy(adminOnlyKinds: {Notebook.kind});

/// The item that names a shared notebook inside its space.
const String notebookItemId = 'notebook';

/// Where shared notes are written. [NotesRepository] sends a note here when
/// it belongs in a space.
abstract interface class SharedNoteStore {
  /// Every note of every shared space this phone has a copy of.
  List<Note> get notes;

  /// Whether [spaceId] holds one note shared on its own (not a notebook).
  bool isSingle(String spaceId);

  Future<void> saveNote(Note note);
  Future<void> deleteNote(Note note);
}

class SharedNotesState {
  const SharedNotesState({
    this.notebooks = const [],
    this.notes = const [],
    this.ready = false,
    this.available = false,
  });

  /// One per space, shared notebooks and notes shared on their own alike
  /// (see [SharedNotebookInfo.single]).
  final List<Notebook> notebooks;
  final List<Note> notes;

  /// Read at least once since the vault opened.
  final bool ready;

  /// Sharing can be used now (vault open, sharing set up).
  final bool available;

  Notebook? bySpace(String spaceId) {
    for (final n in notebooks) {
      if (n.shared!.spaceId == spaceId) return n;
    }
    return null;
  }
}

class SharedNotesController extends Notifier<SharedNotesState> implements SharedNoteStore {
  ZtLocalStore? _private;
  SharedSpaces? _spaces;
  final Map<String, StreamSubscription<Set<String>>> _watching = {};
  StreamSubscription<Set<String>>? _anchors;
  Future<void>? _running;
  bool _again = false;
  bool _disposed = false;

  static const _anchorPrefix = 'zt.space-anchor/';

  @override
  SharedNotesState build() {
    _disposed = false;
    final store = watchOpenNotesStore(ref);
    final spacesValue = ref.watch(ztSharedSpacesProvider);
    _private = store;
    _spaces = switch (spacesValue) {
      AsyncData(:final value) => value,
      _ => null,
    };
    ref.onDispose(() {
      _disposed = true;
      _anchors?.cancel();
      for (final s in _watching.values) {
        s.cancel();
      }
      _watching.clear();
    });
    if (store == null) return const SharedNotesState();
    if (_spaces == null) {
      // Still opening: wait. Failed (no sharing backend): nothing shared.
      return SharedNotesState(ready: spacesValue.hasError);
    }
    // Keeps the spaces syncing while the vault is open; read again whenever
    // a sync or a membership change lands.
    ref.listen(ztSpacesProvider, (_, _) => reload());
    _anchors = store.changes.listen((ids) {
      if (ids.any((id) => id.startsWith(_anchorPrefix))) reload();
    });
    scheduleMicrotask(reload);
    return const SharedNotesState(available: true);
  }

  @override
  List<Note> get notes => state.notes;

  @override
  bool isSingle(String spaceId) => state.bySpace(spaceId)?.shared?.single ?? false;

  /// Reads every space again from this phone's copies. Completes once a
  /// read that started after this call has finished.
  Future<void> reload() {
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    return _running = () async {
      try {
        do {
          _again = false;
          await _reload();
        } while (_again && !_disposed);
      } finally {
        _running = null;
      }
    }();
  }

  Future<void> _reload() async {
    final store = _private;
    final spaces = _spaces;
    if (store == null || spaces == null || _disposed) return;
    final List<LocalItem> items;
    try {
      items = await store.all();
    } on Object {
      return; // closed by a lock
    }
    final spaceIds = <String>{
      for (final item in items)
        if (!item.deleted && item.itemId.startsWith(_anchorPrefix))
          item.itemId.substring(_anchorPrefix.length),
    };
    final notebooks = <Notebook>[];
    final notes = <Note>[];
    for (final spaceId in spaceIds) {
      final SharedSpace space;
      try {
        space = await spaces.open(spaceId);
      } on Object {
        continue; // not let in yet, or can't vouch for it yet
      }
      if (space.gone) continue;
      _watch(space);
      Map<String, Object?>? meta;
      final inSpace = <Note>[];
      for (final item in await space.store.all()) {
        if (item.deleted) continue;
        final json = item.json;
        if (item.itemId == notebookItemId && Notebook.isNotebookJson(json)) {
          meta = json;
        } else if (Note.isNoteJson(json)) {
          inSpace.add(Note.fromItem(item));
        }
      }
      final single = meta?['single'] == true;
      final id = Notebook.sharedId(spaceId);
      notebooks.add(
        Notebook(
          id: id,
          name: (meta?['name'] as String?) ?? '',
          shared: SharedNotebookInfo(
            spaceId: spaceId,
            isAdmin: space.isAdmin,
            single: single,
            waiting: meta == null,
            members: space.members,
          ),
        ),
      );
      for (final note in inSpace) {
        notes.add(note.located(spaceId, notebookId: single ? null : id));
      }
    }
    for (final gone in _watching.keys.where((id) => !spaceIds.contains(id)).toList()) {
      await _watching.remove(gone)?.cancel();
    }
    if (_disposed) return;
    notebooks.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    state = SharedNotesState(notebooks: notebooks, notes: notes, ready: true, available: true);
  }

  void _watch(SharedSpace space) {
    if (_watching.containsKey(space.id)) return;
    final store = space.store;
    if (store is ZtLocalStore) {
      _watching[space.id] = store.changes.listen((_) => reload());
    }
  }

  SpacesController _require() {
    if (!state.available) throw StateError("Sharing isn't available right now.");
    return ref.read(ztSpacesProvider.notifier);
  }

  /// A note as stored in a space: no notebook (the space is the notebook),
  /// never locked (the lock is this account's own).
  static Map<String, Object?> _json(Note note) =>
      note.copyWith(notebookId: null, locked: false).toItemJson();

  @override
  Future<void> saveNote(Note note) async {
    final spaceId = note.spaceId;
    if (spaceId == null) throw ArgumentError('Not a shared note');
    await _require().save(spaceId, note.id, _json(note));
    await reload();
  }

  @override
  Future<void> deleteNote(Note note) async {
    final spaceId = note.spaceId;
    if (spaceId == null) return;
    await _require().delete(spaceId, note.id);
    await reload();
  }

  /// Makes a new space with this account as its owner, named [name], and
  /// copies [notes] into it. The caller removes the originals. [single]:
  /// one note shared on its own.
  Future<String> create({
    required String name,
    required String myName,
    List<Note> notes = const [],
    bool single = false,
  }) async {
    final controller = _require();
    final space = await controller.create(myName: myName);
    await controller.save(space.id, notebookItemId, {
      'kind': Notebook.kind,
      'name': name,
      if (single) 'single': true,
    });
    for (final note in notes) {
      await controller.save(space.id, note.id, _json(note));
    }
    await reload();
    return space.id;
  }

  /// Renames a shared notebook (owners only).
  Future<void> rename(String spaceId, String name) async {
    final current = state.bySpace(spaceId);
    if (current?.shared?.isAdmin != true) {
      throw StateError("Only the notebook's owners can rename it.");
    }
    await _require().save(spaceId, notebookItemId, {
      'kind': Notebook.kind,
      'name': name,
      if (current!.shared!.single) 'single': true,
    });
    await reload();
  }
}

final sharedNotesProvider = NotifierProvider<SharedNotesController, SharedNotesState>(
  SharedNotesController.new,
);
