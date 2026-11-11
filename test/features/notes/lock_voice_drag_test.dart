import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';
import 'package:zerotrust_notes/src/features/notes/application/note_lock.dart';
import 'package:zerotrust_notes/src/features/notes/application/notes_providers.dart';
import 'package:zerotrust_notes/src/features/notes/presentation/note_editor_page.dart';
import 'package:zerotrust_notes/src/features/notes/presentation/notes_list_page.dart';
import 'package:zerotrust_notes/src/features/voice/voice_recognizer.dart';

import '../../support/fake_sync_backend.dart';
import '../../support/notes_device.dart';
import 'notes_list_page_test.dart' show finish, settle;

class FakeLock implements NoteLockAuthenticator {
  FakeLock(this.approve);
  bool approve;
  int asked = 0;

  @override
  Future<bool> confirm(BuildContext context, WidgetRef ref, {required String reason}) async {
    asked++;
    return approve;
  }
}

class FakeVoice implements VoiceRecognizer {
  FakeVoice(this.words);
  final String words;
  String? languageUsed;

  @override
  Future<VoiceAvailability> initialize() async => VoiceAvailability.ready;

  @override
  Future<List<VoiceLanguage>> languages() async => const [
    VoiceLanguage('en_US', 'English (United States)'),
    VoiceLanguage('he_IL', 'Hebrew (Israel)'),
  ];

  @override
  Future<String?> systemLanguageId() async => 'en_US';

  @override
  Future<void> listen({
    required String languageId,
    required void Function(String text, bool isFinal) onText,
    required void Function(VoiceError error) onError,
    required void Function() onDone,
  }) async {
    languageUsed = languageId;
    onText(words, true);
    onDone();
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {}
}

void main() {
  const timeout = Timeout(Duration(seconds: 60));
  late Device phone;

  Future<void> start(
    WidgetTester tester,
    Widget home, {
    List<Override> overrides = const [],
  }) async {
    phone = Device('phone', FakeSyncBackend(), overrides: overrides);
    unawaited(phone.unlock());
    for (var i = 0; i < 50 && phone.container.read(notesRepositoryProvider) == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: phone.container,
        child: MaterialApp(localizationsDelegates: const [AppL10n.delegate, ...ZtLanguages.delegates], home: home),
      ),
    );
    await settle(tester);
  }

  Future<T> real<T>(WidgetTester tester, Future<T> Function() body) async =>
      (await tester.runAsync(body)) as T;

  testWidgets(
    'a locked note shows only its title and opens after the phone lock',
    timeout: timeout,
    (tester) async {
      final lock = FakeLock(false);
      await start(
        tester,
        const NotesListPage(),
        overrides: [noteLockAuthenticatorProvider.overrideWithValue(lock)],
      );
      await real(tester, () => phone.repo.createNote(title: 'Bank', body: 'pin 1234'));
      final created = (await real(tester, phone.repo.fetchAll)).single;
      await real(tester, () => phone.repo.updateNote(created.copyWith(locked: true)));
      await settle(tester);

      expect(find.text('Bank'), findsOneWidget);
      expect(find.text('pin 1234'), findsNothing);
      expect(find.text('Locked'), findsOneWidget);

      await tester.tap(find.text('Bank'));
      await settle(tester);
      expect(lock.asked, 1);
      expect(find.text('Confirm it\'s you to open this note.'), findsOneWidget);
      expect(find.byKey(const Key('note_body_field')), findsNothing);

      lock.approve = true;
      await tester.tap(find.text('Unlock'));
      await settle(tester);
      expect(find.text('pin 1234'), findsOneWidget);
      await finish(tester, phone);
    },
  );

  testWidgets('Lock note in the editor saves the lock', timeout: timeout, (tester) async {
    await start(tester, const NoteEditorPage());
    await tester.enterText(find.byKey(const Key('note_title_field')), 'Secret');
    await settle(tester);
    await tester.tap(find.byTooltip('More options'));
    await settle(tester);
    // The menu is longer than the test screen; scroll to the entry.
    await tester.ensureVisible(find.text('Lock note'));
    await settle(tester);
    await tester.tap(find.text('Lock note'));
    await settle(tester);
    expect((await real(tester, phone.repo.fetchAll)).single.locked, isTrue);
    await finish(tester, phone);
  });

  testWidgets('a voice note in Hebrew is added to the note, right to left', timeout: timeout, (
    tester,
  ) async {
    final voice = FakeVoice('לקנות חלב');
    await start(
      tester,
      const NoteEditorPage(startWithVoice: true),
      overrides: [voiceRecognizerProvider.overrideWithValue(voice)],
    );
    expect(find.text('Voice note'), findsWidgets);

    // Pick Hebrew: listening starts again in it.
    await tester.tap(find.byKey(const Key('voice_language')));
    await settle(tester);
    await tester.tap(find.text('Hebrew (Israel)').last);
    await settle(tester);
    expect(voice.languageUsed, 'he_IL');

    await tester.tap(find.text('Add to note'));
    await settle(tester);
    final body = tester.widget<TextField>(find.byKey(const Key('note_body_field')));
    expect(body.controller!.text, contains('לקנות חלב'));
    expect(body.textDirection, TextDirection.rtl);
    expect((await real(tester, phone.repo.fetchAll)).single.body, contains('לקנות חלב'));
    await finish(tester, phone);
  });

  testWidgets('dragging a note onto another moves it there', timeout: timeout, (tester) async {
    await start(tester, const NotesListPage());
    for (final title in ['Third', 'Second', 'First']) {
      await real(tester, () => phone.repo.createNote(title: title, body: ''));
      await real(tester, () => Future<void>.delayed(const Duration(milliseconds: 5)));
    }
    await tester.tap(find.byTooltip('Show as list'));
    await settle(tester);

    double top(String title) => tester.getTopLeft(find.text(title)).dy;
    expect(top('First'), lessThan(top('Second')));

    final gesture = await tester.startGesture(tester.getCenter(find.text('First')));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(tester.getCenter(find.text('Third')));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await settle(tester);

    expect(top('Second'), lessThan(top('Third')));
    expect(top('Third'), lessThan(top('First')));
    await finish(tester, phone);
  });
}
