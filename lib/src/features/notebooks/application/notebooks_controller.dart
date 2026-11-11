import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../notes/application/notes_providers.dart';
import '../../sharing/shared_notebooks.dart';
import '../data/notebooks_repository.dart';
import '../domain/notebook.dart';

/// `null` whenever the store isn't open — mirrors [notesRepositoryProvider]'s
/// "no access while locked" contract.
final notebooksRepositoryProvider = Provider<NotebooksRepository?>((ref) {
  final store = watchOpenNotesStore(ref);
  if (store == null) return null;
  return NotebooksRepository(store: store, sync: syncForWrites(ref));
});

/// The account's own notebooks.
final ownNotebooksProvider = StreamProvider<List<Notebook>>((ref) {
  final repository = ref.watch(notebooksRepositoryProvider);
  if (repository == null) return const Stream.empty();
  return repository.watchAll();
});

/// Own and shared notebooks, by name. Notes shared on their own aren't
/// notebooks and aren't listed; neither are spaces still waiting to be let
/// in.
final notebooksListProvider = Provider<AsyncValue<List<Notebook>>>((ref) {
  final shared = ref.watch(sharedNotesProvider.select((s) => s.notebooks));
  return ref.watch(ownNotebooksProvider).whenData((own) {
    final visible = [
      for (final n in shared)
        if (!n.shared!.single && !n.shared!.waiting) n,
    ];
    if (visible.isEmpty) return own;
    return [...own, ...visible]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  });
});
