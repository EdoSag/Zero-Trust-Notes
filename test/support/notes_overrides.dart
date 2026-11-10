import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/main.dart';
import 'package:zerotrust_notes/src/core/db/local_note_vault.dart';
import 'package:zerotrust_notes/src/features/legacy_import/previous_store_migration.dart';
import 'package:zerotrust_notes/src/features/notes/application/notes_providers.dart';
import 'package:zerotrust_notes/src/features/reminders/reminder_scheduler.dart';

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
/// in-memory encrypted store per unlock, [server] for sync, [files] for
/// attachments (shared between devices of one test), and [deviceId].
List<Override> notesTestOverrides({
  required SyncBackend server,
  required String deviceId,
  PreviousNotesStoreFile? previousStore,
  AttachmentBackend? files,
}) => [
  ztAppConfigProvider.overrideWithValue(notesAppConfig),
  ztSyncBackendProvider.overrideWithValue(server),
  ztDeviceIdStoreProvider.overrideWithValue(InMemoryDeviceIdStore()..id = deviceId),
  ztPreferencesStoreProvider.overrideWithValue(InMemoryPreferencesStore()),
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
  reminderSchedulerProvider.overrideWithValue(NoopReminderScheduler()),
  ..._attachmentOverrides(files ?? InMemoryAttachmentBackend()),
];

List<Override> _attachmentOverrides(AttachmentBackend files) {
  // One device's encrypted copies, kept across lock and unlock.
  final cache = InMemoryAttachmentCache();
  return [
    ztAttachmentsProvider.overrideWith((ref) async {
      final unlocked = ref.watch(
        vaultControllerProvider.select((v) => v is VaultUnlocked ? v.appKey : null),
      );
      if (unlocked == null) throw const VaultIsLocked();
      final attachments = ZtAttachments(
        appId: 'notes',
        userId: 'test-user',
        backend: files,
        cache: cache,
      );
      // As the real provider does: retry waiting uploads after each sync.
      ref.listen(ztSyncControllerProvider.select((s) => s.lastSyncedAt), (previous, next) {
        if (next != null && next != previous) attachments.flush().catchError((Object _) {});
      });
      return attachments;
    }),
  ];
}
