import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';

import '../notes/application/notes_providers.dart';
import '../notes/domain/note.dart';
import '../notes/presentation/note_editor_page.dart';
import 'note_template.dart';
import 'templates_repository.dart';

/// Built-in templates first, then the person's own.
List<NoteTemplate> allTemplates(WidgetRef ref, AppL10n l) => [
  ...NoteTemplate.builtIns(l),
  ...ref.watch(ownTemplatesProvider).value ?? const <NoteTemplate>[],
];

/// The daily note's template: the one picked in Templates (own or
/// built-in), else the built-in journal. Read from the store, so it is
/// right even before the templates screen has ever loaded.
Future<NoteTemplate> dailyTemplate(TemplatesRepository? repository, AppL10n l) async {
  final builtIns = NoteTemplate.builtIns(l);
  if (repository == null) return builtIns.first;
  final id = await repository.dailyId();
  final all = [...builtIns, ...await repository.fetchAll()];
  return all.where((t) => t.id == id).firstOrNull ?? builtIns.first;
}

/// Opens a new note made from [template], in [notebookId]. Nothing is
/// saved until something is typed.
Future<void> openNoteFromTemplate(
  BuildContext context,
  NoteTemplate template, {
  String? notebookId,
  String? tagId,
  String? title,
}) {
  final fill = template.fill(DateTime.now(), localeName: context.l10n.localeName);
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => NoteEditorPage(
        initialTitle: title ?? fill.title,
        initialBody: fill.body,
        initialChecklist: fill.checklist,
        initialNotebookId: notebookId,
        initialTagId: tagId,
      ),
    ),
  );
}

/// Today's note (N-5): the note titled with today's date (2026-11-22),
/// or a new one from the daily template.
Future<void> openDailyNote(BuildContext context, WidgetRef ref) async {
  final today = NoteTemplate.isoDate(DateTime.now());
  final notes = ref.read(notesListProvider).value ?? const <Note>[];
  final existing = notes.where((n) => n.title.trim() == today).firstOrNull;
  if (existing != null) {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => NoteEditorPage(note: existing)));
    return;
  }
  final l10n = context.l10n;
  final template = await dailyTemplate(ref.read(templatesRepositoryProvider), l10n);
  if (!context.mounted) return;
  await openNoteFromTemplate(context, template, title: today);
}

/// Picks a template for a new note. Returns null when dismissed.
Future<NoteTemplate?> showTemplatePicker(BuildContext context) => showModalBottomSheet<NoteTemplate>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => const _TemplatePicker(),
);

class _TemplatePicker extends ConsumerWidget {
  const _TemplatePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final templates = allTemplates(ref, l10n);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(l10n.newFromTemplate, style: Theme.of(context).textTheme.titleLarge),
            ),
            for (final template in templates)
              ListTile(
                key: ValueKey('template_${template.id}'),
                leading: Icon(template.isChecklist ? Icons.checklist : Icons.description_outlined),
                title: Text(template.name),
                subtitle: template.builtIn ? Text(l10n.builtInTemplate) : null,
                onTap: () => Navigator.of(context).pop(template),
              ),
            ListTile(
              leading: const Icon(Icons.tune),
              title: Text(l10n.manageTemplates),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: (_) => const TemplatesPage()));
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Saves [note] as a template, asking for its name.
Future<void> saveNoteAsTemplate(BuildContext context, WidgetRef ref, Note note) async {
  final repository = ref.read(templatesRepositoryProvider);
  if (repository == null) return;
  final name = await _askName(
    context,
    title: context.l10n.saveAsTemplate,
    initial: note.title.trim().isEmpty ? context.l10n.untitled : note.title.trim(),
  );
  if (name == null || !context.mounted) return;
  await repository.add((id) => NoteTemplate.fromNote(note, id: id, name: name));
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(context.l10n.templateSaved(name)), duration: const Duration(seconds: 3)),
  );
}

Future<String?> _askName(BuildContext context, {required String title, String initial = ''}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        key: const Key('template_name'),
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: context.l10n.templateName),
        onSubmitted: (v) {
          if (v.trim().isNotEmpty) Navigator.of(dialogContext).pop(v.trim());
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          key: const Key('template_name_save'),
          onPressed: () {
            final v = controller.text.trim();
            if (v.isNotEmpty) Navigator.of(dialogContext).pop(v);
          },
          child: Text(context.l10n.save),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

/// Settings > Templates: every template, which one the daily note starts
/// from, and renaming or deleting the person's own.
class TemplatesPage extends ConsumerWidget {
  const TemplatesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final templates = allTemplates(ref, l10n);
    final dailyId = ref.watch(dailyTemplateIdProvider).value ?? NoteTemplate.builtIns(l10n).first.id;
    final repository = ref.watch(templatesRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.templates)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(l10n.templatesHelp('{{date}}, {{longdate}}, {{weekday}}, {{time}}'), style: Theme.of(context).textTheme.bodyMedium),
          ),
          RadioGroup<String>(
            groupValue: dailyId,
            onChanged: (id) {
              if (id == null || repository == null) return;
              repository.setDaily(id);
            },
            child: Column(
              children: [
                for (final template in templates)
                  ListTile(
                    key: ValueKey('templates_row_${template.id}'),
                    leading: Radio<String>(value: template.id),
                    title: Text(template.name),
                    subtitle: Text(
                      template.id == dailyId
                          ? l10n.dailyNoteTemplate
                          : template.builtIn
                          ? l10n.builtInTemplate
                          : l10n.ownTemplate,
                    ),
                    trailing: template.builtIn || repository == null
                        ? null
                        : PopupMenuButton<String>(
                            tooltip: l10n.moreOptions,
                            onSelected: (action) async {
                              if (action == 'rename') {
                                final name = await _askName(
                                  context,
                                  title: l10n.renameTemplate,
                                  initial: template.name,
                                );
                                if (name != null) await repository.save(template.copyWith(name: name));
                              } else if (action == 'delete') {
                                await repository.delete(template);
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(value: 'rename', child: Text(l10n.renameTemplate)),
                              PopupMenuItem(value: 'delete', child: Text(l10n.deleteTemplate)),
                            ],
                          ),
                    onTap: () => openNoteFromTemplate(context, template),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
