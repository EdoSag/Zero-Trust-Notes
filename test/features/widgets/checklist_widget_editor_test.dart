import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';
import 'package:zerotrust_notes/src/features/notes/application/notes_providers.dart';
import 'package:zerotrust_notes/src/features/notes/domain/checklist_item.dart';
import 'package:zerotrust_notes/src/features/notes/presentation/note_editor_page.dart';
import 'package:zerotrust_notes/src/features/widgets/application/checklist_widget_ticks.dart';

import '../../support/fake_sync_backend.dart';
import '../../support/notes_device.dart';
import '../notes/notes_list_page_test.dart' show finish, settle;

void main() {
  testWidgets('a widget tick saved while the editor is open is kept by its next save',
      timeout: const Timeout(Duration(seconds: 60)), (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final phone = Device('phone', FakeSyncBackend());
    unawaited(phone.unlock());
    for (var i = 0; i < 50 && phone.container.read(notesRepositoryProvider) == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    const milk = ChecklistItem(id: 'a', text: 'Milk');
    const bread = ChecklistItem(id: 'b', text: 'Bread');
    final note = (await tester.runAsync(
      () => phone.repo.createNote(
        title: 'Shopping',
        body: ChecklistItem.toMarkdown([milk, bread]),
        checklist: const [milk, bread],
      ),
    ))!;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: phone.container,
        child: MaterialApp(
          theme: ZtTheme.light(),
          localizationsDelegates: const [AppL10n.delegate, ...ZtLanguages.delegates],
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute<void>(builder: (_) => NoteEditorPage(note: note))),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('open'));
    await settle(tester);

    // Milk is ticked on the home screen while the note is open.
    final ticked = (await tester.runAsync(
      () => phone.repo.updateNote(note.withChecklist([milk.copyWith(checked: true), bread])),
    ))!;
    phone.container.read(widgetTickedNoteProvider.notifier).saved(ticked);
    await settle(tester);

    // Then only the title is edited here.
    await tester.enterText(find.byKey(const Key('note_title_field')), 'Groceries');
    await tester.pageBack();
    await settle(tester);

    final saved = (await tester.runAsync(() => phone.repo.fetchAll()))!.single;
    expect(saved.title, 'Groceries');
    expect({for (final item in saved.checklist!) item.text: item.checked}, {
      'Milk': true,
      'Bread': false,
    });
    await finish(tester, phone);
  });
}
