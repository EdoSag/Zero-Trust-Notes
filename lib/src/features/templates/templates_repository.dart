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

  /// Where a built-in daily template choice is kept: one small item, with
  /// a `kind`, so older Notes builds skip it like templates.
  static const settingsId = 'notes-template-settings';
  static const settingsKind = 'templateSettings';

  /// Makes [templateId] (an own template, or a built-in's `builtin:` id)
  /// the daily note's template; every other own template stops being it.
  /// Null means the built-in journal.
  Future<void> setDaily(String? templateId) async {
    for (final template in await fetchAll()) {
      final daily = template.id == templateId;
      if (template.daily != daily) await save(template.copyWith(daily: daily));
    }
    final builtIn = templateId != null && templateId.startsWith(NoteTemplate.builtInPrefix)
        ? templateId
        : null;
    if (await _dailyBuiltIn() != builtIn) {
      await (await _sync()).save(settingsId, {'kind': settingsKind, 'dailyBuiltIn': builtIn});
    }
  }

  /// The daily note's template id: an own template marked daily, else the
  /// chosen built-in, else null (the built-in journal).
  Future<String?> dailyId() async {
    final own = (await fetchAll()).where((t) => t.daily).firstOrNull;
    return own?.id ?? await _dailyBuiltIn();
  }

  Future<String?> _dailyBuiltIn() async {
    final json = (await _store.get(settingsId))?.json;
    if (json == null || json['kind'] != settingsKind) return null;
    return json['dailyBuiltIn'] as String?;
  }
}

final templatesRepositoryProvider = Provider<TemplatesRepository?>((ref) {
  final store = watchOpenNotesStore(ref);
  if (store == null) return null;
  return TemplatesRepository(store: store, sync: syncForWrites(ref));
});

/// The daily note's template id (see [TemplatesRepository.dailyId]),
/// read again whenever the templates change.
final dailyTemplateIdProvider = FutureProvider<String?>((ref) async {
  ref.watch(ownTemplatesProvider);
  return ref.watch(templatesRepositoryProvider)?.dailyId();
});

/// The person's own templates.
final ownTemplatesProvider = StreamProvider<List<NoteTemplate>>((ref) {
  final repository = ref.watch(templatesRepositoryProvider);
  if (repository == null) return const Stream.empty();
  return repository.watchAll();
});
