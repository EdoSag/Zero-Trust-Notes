import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/local_note_vault.dart';
import '../../vault/application/vault_controller.dart';
import '../../vault/application/vault_state.dart';
import '../data/notebooks_repository.dart';

/// `null` whenever the vault isn't open — mirrors [notesRepositoryProvider]'s
/// "no access while locked" contract. Uses [unlockedFieldsOf] (rather than
/// matching [VaultUnlocked] alone) so notebook/tag management stays
/// available during sync too, since it touches plaintext tables the sync
/// encryption pipeline never has a reason to lock out.
final notebooksRepositoryProvider = Provider<NotebooksRepository?>((ref) {
  final fields = unlockedFieldsOf(ref.watch(vaultControllerProvider));
  if (fields == null) return null;
  return NotebooksRepository(vault: fields.vault);
});

final notebooksListProvider = StreamProvider<List<Notebook>>((ref) {
  final repository = ref.watch(notebooksRepositoryProvider);
  if (repository == null) return const Stream.empty();
  return repository.watchAll();
});
