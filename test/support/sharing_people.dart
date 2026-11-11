import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/src/features/notebooks/application/notebooks_controller.dart';
import 'package:zerotrust_notes/src/features/notebooks/domain/notebook.dart';
import 'package:zerotrust_notes/src/features/notes/application/notes_providers.dart';
import 'package:zerotrust_notes/src/features/notes/domain/note.dart';
import 'package:zerotrust_notes/src/features/sharing/shared_notebooks.dart';

import 'fake_account_backend.dart';
import 'fake_sync_backend.dart';
import 'notes_device.dart';

const alice = '00000000-0000-4000-8000-00000000000a';
const bob = '00000000-0000-4000-8000-00000000000b';

class FakeUserAccount extends AccountService {
  FakeUserAccount(this.id) : super(FakeAccountBackend(onUserChanged: (_) {}));
  final String id;
  @override
  String? get currentUserId => id;
}

class MemorySpaceOpener implements SpaceStoreOpener {
  final Map<String, InMemoryItemStore> stores = {};
  @override
  Future<LocalItemStore> open(String spaceId) async =>
      stores.putIfAbsent(spaceId, InMemoryItemStore.new);
  @override
  Future<void> delete(String spaceId) async => stores.remove(spaceId);
  @override
  Future<void> closeAll() async {}
}

/// One person's phone: their own account (own vault server) on the shared
/// spaces server.
class Person {
  Person(this.userId, InMemorySpaceServer spaces, this.seed)
    : device = Device(
        userId,
        FakeSyncBackend(),
        overrides: [
          accountServiceProvider.overrideWithValue(FakeUserAccount(userId)),
          ztSpaceBackendProvider.overrideWithValue(spaces.backendFor(userId)),
          ztSpaceStoreOpenerProvider.overrideWithValue(MemorySpaceOpener()),
          ztSpacePolicyProvider.overrideWithValue(notesSpacePolicy),
        ],
      );

  final String userId;
  final int seed;
  final Device device;

  ProviderContainer get c => device.container;
  SharedNotesController get shared => c.read(sharedNotesProvider.notifier);
  SpacesController get spaces => c.read(ztSpacesProvider.notifier);

  Future<void> open() async {
    c.listen(allNotesProvider, (_, _) {});
    c.listen(notebooksListProvider, (_, _) {});
    c.listen(ztSpacesProvider, (_, _) {});
    await device.unlock(seed: seed);
    await until(() => c.read(sharedNotesProvider).available && c.read(ztSpacesProvider).ready);
  }

  List<Note> get notes => c.read(allNotesProvider).value ?? const [];
  List<Notebook> get notebooks => c.read(notebooksListProvider).value ?? const [];
  Note note(String title) => notes.singleWhere((n) => n.title == title);

  /// Pushes and pulls every space, then reads them again.
  Future<void> syncSpaces() async {
    await spaces.refresh();
    for (final e in c.read(ztSpacesProvider).entries) {
      await spaces.syncNow(e.info.id);
    }
    await shared.reload();
    await device.sync();
  }
}

Future<void> until(bool Function() test, {String? reason}) async {
  for (var i = 0; i < 400; i++) {
    if (test()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('never happened${reason == null ? '' : ': $reason'}');
}

