import 'package:uuid/uuid.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../../../shared/watch_store.dart';
import '../../notes/domain/note.dart';
import '../domain/tag.dart';

/// Tags live in the same encrypted, synced store as notes (see [Tag]); a
/// note lists the tags it carries in `Note.tagIds`.
class TagsRepository {
  TagsRepository({required this._store, required this._sync});

  final ZtLocalStore _store;
  final Future<SyncController> Function() _sync;
  static const _uuid = Uuid();

  /// The tags by name, and again after every change.
  Stream<List<Tag>> watchAll() => watchStore(_store, fetchAll);

  Future<List<Tag>> fetchAll() async {
    final tags = [
      for (final item in await _store.liveItems())
        if (Tag.isTagJson(item.json)) Tag.fromItem(item),
    ];
    return tags..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<Tag> create(String name, {String? colorHex}) async {
    final tag = Tag(id: _uuid.v4(), name: name, colorHex: colorHex);
    await (await _sync()).save(tag.id, tag.toItemJson());
    return tag;
  }

  /// Takes the tag off every note that carries it, then removes it.
  Future<void> delete(String id) async {
    final sync = await _sync();
    for (final item in await _store.liveItems()) {
      if (!Note.isNoteJson(item.json)) continue;
      final note = Note.fromItem(item);
      if (note.tagIds.contains(id)) {
        await sync.save(note.id, note.copyWith(tagIds: [...note.tagIds]..remove(id)).toItemJson());
      }
    }
    await sync.delete(id);
  }
}
