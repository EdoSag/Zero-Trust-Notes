import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/local_note_vault.dart';
import '../../vault/application/vault_controller.dart';
import '../../vault/application/vault_state.dart';
import '../data/tags_repository.dart';

final tagsRepositoryProvider = Provider<TagsRepository?>((ref) {
  final fields = unlockedFieldsOf(ref.watch(vaultControllerProvider));
  if (fields == null) return null;
  return TagsRepository(vault: fields.vault);
});

final tagsListProvider = StreamProvider<List<Tag>>((ref) {
  final repository = ref.watch(tagsRepositoryProvider);
  if (repository == null) return const Stream.empty();
  return repository.watchAll();
});

final noteTagIdsProvider = StreamProvider.family<List<String>, String>((ref, noteId) {
  final repository = ref.watch(tagsRepositoryProvider);
  if (repository == null) return const Stream.empty();
  return repository.watchTagIdsForNote(noteId);
});
