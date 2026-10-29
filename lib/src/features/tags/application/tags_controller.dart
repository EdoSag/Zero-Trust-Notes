import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../notes/application/notes_providers.dart';
import '../data/tags_repository.dart';
import '../domain/tag.dart';

final tagsRepositoryProvider = Provider<TagsRepository?>((ref) {
  final store = watchOpenNotesStore(ref);
  if (store == null) return null;
  return TagsRepository(store: store, sync: syncForWrites(ref));
});

final tagsListProvider = StreamProvider<List<Tag>>((ref) {
  final repository = ref.watch(tagsRepositoryProvider);
  if (repository == null) return const Stream.empty();
  return repository.watchAll();
});
