import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../notes/application/notes_providers.dart';
import '../data/notebooks_repository.dart';
import '../domain/notebook.dart';

/// `null` whenever the store isn't open — mirrors [notesRepositoryProvider]'s
/// "no access while locked" contract.
final notebooksRepositoryProvider = Provider<NotebooksRepository?>((ref) {
  final store = watchOpenNotesStore(ref);
  if (store == null) return null;
  return NotebooksRepository(store: store, sync: syncForWrites(ref));
});

final notebooksListProvider = StreamProvider<List<Notebook>>((ref) {
  final repository = ref.watch(notebooksRepositoryProvider);
  if (repository == null) return const Stream.empty();
  return repository.watchAll();
});
