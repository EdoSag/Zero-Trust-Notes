import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/src/features/notes/application/notes_providers.dart';
import 'package:zerotrust_notes/src/features/notes/data/notes_repository.dart';
import 'package:zerotrust_notes/src/features/sync/application/conflict_copies.dart';

import 'fake_sync_backend.dart';
import 'notes_overrides.dart';

/// The shared server as one device reaches it: unreachable while [online]
/// is off.
class DeviceLink implements SyncBackend {
  DeviceLink(this.server);
  final FakeSyncBackend server;
  bool online = true;

  void _check() {
    if (!online) throw Exception('offline');
  }

  @override
  Future<List<RemoteItem>> pull(String app, {DateTime? since}) async {
    _check();
    return server.pull(app, since: since);
  }

  @override
  Future<List<RemoteItem>> fetch(String app, Set<String> itemIds) async {
    _check();
    return server.fetch(app, itemIds);
  }

  @override
  Future<Set<String>> pushAll(String app, List<RemoteItem> items) async {
    _check();
    return server.pushAll(app, items);
  }

  @override
  Future<void> Function() subscribe(String app, void Function(RemoteItem) onChange) =>
      server.subscribe(app, onChange);
}

/// One install of the app: its own in-memory store and device id, on a
/// shared fake server, unlocked with the same account key.
class Device {
  Device(String id, FakeSyncBackend server) : link = DeviceLink(server) {
    container = ProviderContainer(
      overrides: notesTestOverrides(server: link, deviceId: id),
    );
  }

  final DeviceLink link;
  late final ProviderContainer container;

  Future<void> unlock() async {
    // As the notes list does: keep sync and conflict copies running.
    container.listen(ztSyncControllerProvider, (_, _) {});
    container.listen(conflictCopiesProvider, (_, _) {});
    await container
        .read(vaultControllerProvider.notifier)
        .unlock(Uint8List.fromList(List.generate(32, (i) => i)));
    await container.read(notesStoreProvider.future);
    await container.read(ztSyncEngineProvider.future);
  }

  NotesRepository get repo => container.read(notesRepositoryProvider)!;

  Future<List<(String, String)>> notes() async {
    final all = await repo.fetchAll();
    return [for (final n in all) (n.title, n.body)];
  }

  Future<void> sync() async {
    await container.read(ztSyncControllerProvider.notifier).syncNow();
    // Let conflict copies land.
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
