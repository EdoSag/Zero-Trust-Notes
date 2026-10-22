import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/main.dart';
import 'package:zerotrust_notes/src/core/db/local_note_vault.dart';
import 'package:zerotrust_notes/src/features/legacy_import/previous_store_migration.dart';
import 'package:zerotrust_notes/src/features/notes/application/notes_providers.dart';

/// No earlier Notes store on this "device".
class NoPreviousStore implements PreviousNotesStoreFile {
  @override
  Future<bool> exists() async => false;
  @override
  Future<LocalNoteVault> open(String key) => throw UnimplementedError();
  @override
  Future<void> delete() async {}
}

/// Everything Notes needs to run without Supabase, a keychain or a disk: an
/// in-memory encrypted store per unlock, [server] for sync, and [deviceId].
List<Override> notesTestOverrides({
  required SyncBackend server,
  required String deviceId,
  PreviousNotesStoreFile? previousStore,
}) => [
  ztAppConfigProvider.overrideWithValue(notesAppConfig),
  ztSyncBackendProvider.overrideWithValue(server),
  ztDeviceIdStoreProvider.overrideWithValue(InMemoryDeviceIdStore()..id = deviceId),
  ztLocalStoreProvider.overrideWith((ref) async {
    final appKey = ref.watch(
      vaultControllerProvider.select((v) => v is VaultUnlocked ? v.appKey : null),
    );
    if (appKey == null) throw const VaultIsLocked();
    final store = await ZtLocalStore.open(appKey: appKey);
    ref.onDispose(store.close);
    return store;
  }),
  previousNotesStoreFileProvider.overrideWithValue(previousStore ?? NoPreviousStore()),
];
