import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../../shared/watch_store.dart';
import '../notes/application/notes_providers.dart';
import 'note_template.dart';

/// The person's own templates, in the same encrypted, synced store as their
/// notes (see [NoteTemplate]).
class TemplatesRepository {
  TemplatesRepository({required this._store, required this._sync});

  final ZtLocalStore _store;
  final Future<SyncController> Function() _sync;
  static const _uuid = Uuid();

  Stream<List<NoteTemplate>> watchAll() => watchStore(_store, fetchAll);

  /// By name.
  Future<List<NoteTemplate>> fetchAll() async {
    final templates = [
      for (final item in await _store.liveItems())
        if (NoteTemplate.isTemplateJson(item.json)) NoteTemplate.fromItem(item),
    ];
    return templates..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// Saves [template] under a new id.
  Future<NoteTemplate> add(NoteTemplate Function(String id) template) async {
    final made = template(_uuid.v4());
    await (await _sync()).save(made.id, made.toItemJson());
    return made;
  }

  Future<void> save(NoteTemplate template) async {
    if (template.builtIn) return;
    await (await _sync()).save(template.id, template.toItemJson());
  }

  Future<void> delete(NoteTemplate template) async {
    if (template.builtIn) return;
    await (await _sync()).delete(template.id);
  }

  /// Makes [templateId] the daily note's template (or the built-in journal
  /// when null): every other own template stops being it.
  Future<void> setDaily(String? templateId) async {
    for (final template in await fetchAll()) {
      final daily = template.id == templateId;
      if (template.daily != daily) await save(template.copyWith(daily: daily));
    }
  }
}

final templatesRepositoryProvider = Provider<TemplatesRepository?>((ref) {
  final store = watchOpenNotesStore(ref);
  if (store == null) return null;
  return TemplatesRepository(store: store, sync: syncForWrites(ref));
});

/// The person's own templates.
final ownTemplatesProvider = StreamProvider<List<NoteTemplate>>((ref) {
  final repository = ref.watch(templatesRepositoryProvider);
  if (repository == null) return const Stream.empty();
  return repository.watchAll();
});
