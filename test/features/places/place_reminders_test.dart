import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';
import 'package:zerotrust_notes/src/features/notes/application/notes_providers.dart';
import 'package:zerotrust_notes/src/features/notes/domain/note.dart';
import 'package:zerotrust_notes/src/features/notes/domain/notes_filter.dart';
import 'package:zerotrust_notes/src/features/notes/presentation/note_editor_page.dart';
import 'package:zerotrust_notes/src/features/places/note_place_reminder.dart';
import 'package:zerotrust_notes/src/features/places/place_providers.dart';
import 'package:zt_places/zt_places.dart';

import '../../support/fake_sync_backend.dart';
import '../../support/notes_device.dart';
import '../notes/notes_list_page_test.dart' show finish, settle;

const home = ZtPlace(id: 'home', name: 'Home', latitude: 32.08, longitude: 34.78);

NotePlaceReminder reminder({ZtPlaceTrigger trigger = ZtPlaceTrigger.arrive, int minute = 0}) =>
    NotePlaceReminder(place: home, trigger: trigger, setAt: DateTime.utc(2026, 11, 11, 10, minute));

Note note(String id, {String title = 'Buy milk', NotePlaceReminder? place, DateTime? trashed}) =>
    Note(
      id: id,
      notebookId: null,
      title: title,
      body: '',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      placeReminder: place,
      trashedAt: trashed,
    );

void main() {
  const timeout = Timeout(Duration(seconds: 60));

  group('note JSON', () {
    test('round trip, written only when set', () {
      final n = note('n1', place: reminder(trigger: ZtPlaceTrigger.leave));
      final json = n.toItemJson();
      expect(json['placeReminder'], isA<Map<String, Object?>>());
      final back = Note.fromItem(
        LocalItem(itemId: 'n1', json: json, updatedAt: DateTime.utc(2026)),
      );
      expect(back.placeReminder, n.placeReminder);
      expect(back.extra, isEmpty);
      expect(note('n2').toItemJson().containsKey('placeReminder'), isFalse);
    });

    test('a malformed reminder reads as none instead of failing the note', () {
      final back = Note.fromItem(
        LocalItem(
          itemId: 'n1',
          json: {
            'title': 't',
            'body': '',
            'placeReminder': {'place': 'x'},
          },
          updatedAt: DateTime.utc(2026),
        ),
      );
      expect(back.placeReminder, isNull);
      expect(back.title, 't');
    });

    test('the OS id carries when it was set, so setting it again re-arms it', () {
      expect(reminder().idFor('n1'), isNot(reminder(minute: 5).idFor('n1')));
      expect(NotePlaceReminder.noteIdOf(reminder().idFor('a@b')), 'a@b');
    });
  });

  test('what reaches the OS: title and place only, not trashed notes', () {
    final list = placeRemindersFor([
      note('a', place: reminder()),
      note(
        'b',
        title: '  ',
        place: reminder(trigger: ZtPlaceTrigger.leave),
      ),
      note('c', place: reminder(), trashed: DateTime.utc(2026)),
      note('d'),
    ]);
    expect(list.map((r) => r.payload), ['a', 'b']);
    expect(list.first.title, 'Buy milk');
    expect(list.first.body, 'When you arrive at Home');
    expect(list.last.title, 'Reminder');
    expect(list.last.body, 'When you leave Home');
    expect(list.first.id, reminder().idFor('a'));
  });

  test('Reminders view lists place reminders after timed ones', () {
    final timed = note('t').copyWith(reminderAt: DateTime.utc(2026, 12));
    final place = note('p', place: reminder());
    final view = const NotesFilter(view: NotesView.reminders).apply([place, note('x'), timed]);
    expect(view.map((n) => n.id), ['t', 'p']);
  });

  test('a fired reminder is dropped only if it is still the one that fired', () async {
    final updated = <Note>[];
    final notes = [note('a', place: reminder(minute: 5)), note('b', place: reminder())];
    final handled = await clearFiredPlaceReminders((n) async => updated.add(n), notes, {
      reminder().idFor('a'),
      reminder().idFor('b'),
      reminder().idFor('gone'),
    });
    expect(handled, hasLength(3));
    expect(updated.map((n) => n.id), ['b']);
    expect(updated.single.placeReminder, isNull);
  });

  test('a fired reminder waits for shared notes that are still loading', () async {
    final updated = <Note>[];
    final fired = {reminder().idFor('own'), reminder().idFor('shared')};
    final own = [note('own', place: reminder())];
    // Right after unlock only the account's own notes are in.
    var handled = await clearFiredPlaceReminders(
      (n) async => updated.add(n),
      own,
      fired,
      allLoaded: false,
    );
    expect(handled, {reminder().idFor('own')});
    // Then the shared note arrives and its reminder is cleared too.
    handled = await clearFiredPlaceReminders((n) async => updated.add(n), [
      ...own,
      note('shared', place: reminder()),
    ], fired.difference(handled));
    expect(handled, {reminder().idFor('shared')});
    expect(updated.map((n) => n.id), ['own', 'shared']);
  });

  test('trash drops the place reminder; saved places sync like notes', timeout: timeout, () async {
    final server = FakeSyncBackend();
    final phone = Device('phone', server);
    final tablet = Device('tablet', server);
    await phone.unlock();
    await tablet.unlock();
    final created = await phone.repo.createNote(title: 'Milk', body: '', placeReminder: reminder());
    expect((await phone.repo.fetchAll()).single.placeReminder, reminder());
    await phone.container.read(savedPlacesRepositoryProvider)!.save(home);
    await phone.sync();
    await tablet.sync();
    expect(await tablet.container.read(savedPlacesRepositoryProvider)!.fetchAll(), [home]);
    // A saved place is not a note.
    expect((await tablet.repo.fetchAll()).map((n) => n.title), ['Milk']);
    final trashed = await phone.repo.moveToTrash(created);
    expect(trashed.placeReminder, isNull);
    phone.container.dispose();
    tablet.container.dispose();
  });

  testWidgets('set a place reminder from the editor', timeout: timeout, (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final phone = Device('phone', FakeSyncBackend());
    unawaited(phone.unlock());
    for (var i = 0; i < 50 && phone.container.read(notesRepositoryProvider) == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    final created = (await tester.runAsync(
      () => phone.repo.createNote(title: 'Buy milk', body: ''),
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
              ).push(MaterialPageRoute<void>(builder: (_) => NoteEditorPage(note: created))),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('open'));
    await settle(tester);
    await tester.tap(find.byTooltip('More options'));
    await settle(tester);
    await tester.tap(find.text('Remind me at a place'));
    await settle(tester);
    expect(find.text('Location reminder'), findsOneWidget);
    await tester.tap(find.byKey(const Key('zt-place-current')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('zt-place-name')), 'Supermarket');
    await tester.tap(find.byKey(const Key('zt-place-done')));
    await settle(tester);

    final chip = find.byKey(const Key('note_place_reminder_chip'));
    expect(chip, findsOneWidget);
    expect(find.text('When you arrive at Supermarket'), findsOneWidget);
    // Beside the title field, below it, inside the screen.
    final title = tester.getRect(find.byKey(const Key('note_title_field')));
    expect(tester.getRect(chip).top, greaterThan(title.bottom - 1));

    await tester.pageBack();
    await settle(tester);
    final saved = (await tester.runAsync(() => phone.repo.fetchAll()))!.single;
    expect(saved.placeReminder!.place.name, 'Supermarket');
    expect(saved.placeReminder!.place.latitude, 32.0853);
    final places = (await tester.runAsync(
      () => phone.container.read(savedPlacesRepositoryProvider)!.fetchAll(),
    ))!;
    expect(places.single.name, 'Supermarket');
    await finish(tester, phone);
  });
  testWidgets(
    'a place reminder that goes off while the note is open is not saved back',
    timeout: timeout,
    (tester) async {
      final phone = Device('phone', FakeSyncBackend());
      unawaited(phone.unlock());
      for (var i = 0; i < 50 && phone.container.read(notesRepositoryProvider) == null; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 20));
      }
      final created = (await tester.runAsync(
        () => phone.repo.createNote(title: 'Buy milk', body: '', placeReminder: reminder()),
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
                ).push(MaterialPageRoute<void>(builder: (_) => NoteEditorPage(note: created))),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('open'));
      await settle(tester);
      expect(find.byKey(const Key('note_place_reminder_chip')), findsOneWidget);

      // It goes off at the shop while the note is open.
      phone.container
          .read(firedPlaceRemindersProvider.notifier)
          .add(created.placeReminder!.idFor(created.id));
      await settle(tester);
      expect(find.byKey(const Key('note_place_reminder_chip')), findsNothing);

      await tester.enterText(find.byKey(const Key('note_title_field')), 'Buy milk and bread');
      await tester.pageBack();
      await settle(tester);
      final saved = (await tester.runAsync(() => phone.repo.fetchAll()))!.single;
      expect(saved.title, 'Buy milk and bread');
      expect(saved.placeReminder, isNull);
      await finish(tester, phone);
    },
  );
}
