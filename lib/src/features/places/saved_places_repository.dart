import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zt_places/zt_places.dart';

import '../../shared/watch_store.dart';

/// "My places" (Home, Office, ...), kept as items of kind `zt.place` in the
/// account's encrypted, synced store, so every device has them and nothing
/// about them is readable outside the vault.
class SavedPlacesRepository {
  SavedPlacesRepository({required this._store, required this._sync});

  final ZtLocalStore _store;
  final Future<SyncController> Function() _sync;

  static const kind = 'zt.place';

  Stream<List<ZtPlace>> watchAll() => watchStore(_store, fetchAll);

  Future<List<ZtPlace>> fetchAll() async {
    final places = [
      for (final item in await _store.liveItems())
        if (item.json?['kind'] == kind) ?ZtPlace.fromJson(item.json),
    ];
    return places..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<void> save(ZtPlace place) async =>
      (await _sync()).save(place.id, {'kind': kind, ...place.toJson()});

  Future<void> delete(String id) async => (await _sync()).delete(id);
}
