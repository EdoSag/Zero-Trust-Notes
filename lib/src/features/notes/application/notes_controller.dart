import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../vault/application/vault_controller.dart';
import '../../vault/application/vault_state.dart';
import '../data/notes_repository.dart';
import '../domain/note.dart';

/// `null` whenever the vault isn't unlocked — callers must treat that as
/// "no notes access", not as an empty vault.
final notesRepositoryProvider = Provider<NotesRepository?>((ref) {
  final vaultState = ref.watch(vaultControllerProvider);
  return switch (vaultState) {
    VaultUnlocked(:final vault, :final payloadKeyBytes) =>
      NotesRepository(vault: vault, payloadKeyBytes: payloadKeyBytes),
    _ => null,
  };
});

final notesListProvider = StreamProvider<List<Note>>((ref) {
  final repository = ref.watch(notesRepositoryProvider);
  if (repository == null) return const Stream.empty();
  return repository.watchAll();
});
