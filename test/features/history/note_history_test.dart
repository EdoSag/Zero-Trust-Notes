import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/l10n/generated/app_l10n.dart';
import 'package:zerotrust_notes/src/features/history/note_history.dart';
import 'package:zerotrust_notes/src/features/notes/application/notes_providers.dart';
import 'package:zerotrust_notes/src/features/notes/domain/note.dart';
import 'package:zerotrust_notes/src/features/notes/presentation/note_editor_page.dart';

import '../../support/fake_sync_backend.dart';
import '../../support/notes_device.dart';
import '../notes/notes_list_page_test.dart' show finish, settle;

/// Runs [work] while the test clock moves, as store reads and writes in a
/// row need (see the templates test).
Future<T> run<T>(WidgetTester tester, Future<T> Function() work) async {
  T? result;
  Object? error;
  var done = false;
  unawaited(
    work()
        .then<void>((v) => result = v, onError: (Object e) => error = e)
        .whenComplete(() => done = true),
  );
  for (var i = 0; i < 40 && !done; i++) {
    await settle(tester);
  }
  if (error != null) throw error!;
  expect(done, isTrue, reason: 'finished');
  return result as T;
}

Future<Device> _phone(WidgetTester tester) async {
  final phone = Device('phone', FakeSyncBackend());
  unawaited(phone.unlock());
  for (var i = 0; i < 50 && phone.container.read(notesRepositoryProvider) == null; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  phone.container.listen(noteHistoryProvider, (_, _) {});
  return phone;
}

void main() {
  test('a version survives the store and is never read as a note', () {
    final version = NoteVersion(
      id: 'v',
      noteId: 'n',
      title: 'T',
      body: 'B',
      savedAt: DateTime.utc(2026, 11, 22, 9),
      recordedAt: DateTime.utc(2026, 11, 22, 10),
    );
    final json = version.toItemJson();
    expect(Note.isNoteJson(json), isFalse);
    final back = NoteVersion.fromItem(LocalItem(itemId: 'v', updatedAt: DateTime.utc(2026), json: json));
    expect((back.noteId, back.title, back.body, back.savedAt), ('n', 'T', 'B', version.savedAt));
  });

  testWidgets('one version per editing session, and none left after delete', (tester) async {
    final phone = await _phone(tester);
    final history = phone.container.read(noteHistoryProvider)!;
    var note = await run(tester, () => phone.repo.createNote(title: 'Plan', body: 'v1'));
    Future<void> edit(Note updated) async {
      await run(tester, () => history.beforeSave(updated, previous: note));
      note = await run(tester, () => phone.repo.updateNote(updated));
    }

    await edit(note.copyWith(body: 'v2'));
    await edit(note.copyWith(body: 'v3'));
    // Same title and text again: nothing to keep.
    await edit(note.copyWith(pinned: true));
    var versions = await run(tester, () => history.versionsOf(note.id));
    expect(versions.map((v) => v.body), ['v1'], reason: 'the text before this session');

    // Deleted for good: its history goes the next time the notes load.
    await run(tester, () => phone.repo.deleteNote(note));
    expect(await run(tester, () => history.forgetDeleted(const {})), 1);
    versions = await run(tester, () => history.versionsOf(note.id));
    expect(versions, isEmpty);
    await finish(tester, phone);
  });

  testWidgets('restore brings back an earlier text and keeps the current one', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final phone = await _phone(tester);
    final history = phone.container.read(noteHistoryProvider)!;
    final first = await run(tester, () => phone.repo.createNote(title: 'Plan', body: 'first draft'));
    final second = first.copyWith(body: 'second draft');
    await run(tester, () => history.beforeSave(second, previous: first));
    final note = await run(tester, () => phone.repo.updateNote(second));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: phone.container,
        child: MaterialApp(
          theme: ZtTheme.light(),
          localizationsDelegates: const [AppL10n.delegate, ...ZtLanguages.delegates],
          home: NoteEditorPage(note: note),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.byTooltip('More options'));
    await settle(tester);
    await tester.tap(find.text('Version history'));
    await settle(tester);
    expect(find.textContaining('first draft'), findsOneWidget);
    await tester.tap(find.textContaining('first draft'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('note_version_restore')));
    await settle(tester);
    expect(find.text('first draft'), findsOneWidget, reason: 'back in the editor');
    await settle(tester);
    final versions = await run(tester, () => history.versionsOf(note.id));
    expect(versions.map((v) => v.body), contains('second draft'));
    final saved = (await run(tester, () => phone.repo.fetchAll())).single;
    expect(saved.body, 'first draft');
    await finish(tester, phone);
  });
}
