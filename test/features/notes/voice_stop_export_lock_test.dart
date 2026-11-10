import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart' show ZtTheme;
import 'package:zerotrust_notes/src/features/export/presentation/export_sheet.dart';
import 'package:zerotrust_notes/src/features/notes/application/note_lock.dart';
import 'package:zerotrust_notes/src/features/notes/application/notes_providers.dart';
import 'package:zerotrust_notes/src/features/voice/voice_note_sheet.dart';
import 'package:zerotrust_notes/src/features/voice/voice_recognizer.dart';

import '../../support/fake_sync_backend.dart';
import '../../support/notes_device.dart';
import 'lock_voice_drag_test.dart' show FakeLock;
import 'notes_list_page_test.dart' show finish, settle;

/// Like Android: the last words arrive only after Stop, then "done".
class StopLateVoice implements VoiceRecognizer {
  StopLateVoice({this.availability = VoiceAvailability.ready});
  final VoiceAvailability availability;
  void Function(String, bool)? _onText;
  void Function()? _onDone;

  @override
  Future<VoiceAvailability> initialize() async => availability;

  @override
  Future<List<VoiceLanguage>> languages() async => const [VoiceLanguage('en_US', 'English')];

  @override
  Future<String?> systemLanguageId() async => 'en_US';

  @override
  Future<void> listen({
    required String languageId,
    required void Function(String text, bool isFinal) onText,
    required void Function(VoiceError error) onError,
    required void Function() onDone,
  }) async {
    _onText = onText;
    _onDone = onDone;
    onText('buy milk', false);
  }

  @override
  Future<void> stop() async {
    scheduleMicrotask(() {
      _onText?.call('buy milk and bread', true);
      _onDone?.call();
    });
  }

  @override
  Future<void> cancel() async {}
}

/// The button showing [label] is laid out inside the screen and a tap on its
/// centre reaches it (a button that failed layout is not drawn at all).
void expectTappableOnScreen(WidgetTester tester, String label) {
  final button = find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  );
  expect(button, findsOneWidget, reason: '"$label" button is missing');
  final rect = tester.getRect(button);
  final screen = Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
  expect(rect.isFinite, isTrue, reason: '"$label" has no finite size');
  expect(screen.contains(rect.center), isTrue, reason: '"$label" is off screen at $rect');
  expect(button.hitTestable(), findsOneWidget, reason: '"$label" cannot be tapped');
}

void main() {
  const timeout = Timeout(Duration(seconds: 60));
  late Device phone;

  Future<void> start(
    WidgetTester tester,
    Widget home, {
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    phone = Device('phone', FakeSyncBackend(), overrides: overrides);
    unawaited(phone.unlock());
    for (var i = 0; i < 50 && phone.container.read(notesRepositoryProvider) == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: phone.container,
        // The real app theme: its full-width buttons vanish inside a Row,
        // which the default theme would hide from these tests.
        child: MaterialApp(theme: ZtTheme.light(), home: home),
      ),
    );
    await settle(tester);
  }

  String? voiceResult;
  final voiceButton = Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () async => voiceResult = await showVoiceNoteSheet(context),
        child: const Text('open'),
      ),
    ),
  );

  testWidgets('Stop then Add to note keeps the last words, once', timeout: timeout, (tester) async {
    voiceResult = null;
    await start(
      tester,
      voiceButton,
      overrides: [voiceRecognizerProvider.overrideWithValue(StopLateVoice())],
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    expect(find.text('buy milk'), findsOneWidget);

    await tester.tap(find.byTooltip('Stop listening'));
    await settle(tester);
    expect(find.text('buy milk and bread'), findsOneWidget);
    expectTappableOnScreen(tester, 'Add to note');

    await tester.tap(find.text('Add to note'));
    await settle(tester);
    expect(voiceResult, 'buy milk and bread');
    await finish(tester, phone);
  });

  testWidgets('Add to note while listening waits for the last words', timeout: timeout, (
    tester,
  ) async {
    voiceResult = null;
    await start(
      tester,
      voiceButton,
      overrides: [voiceRecognizerProvider.overrideWithValue(StopLateVoice())],
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    await tester.tap(find.text('Add to note'));
    await settle(tester);
    expect(voiceResult, 'buy milk and bread');
    await finish(tester, phone);
  });

  testWidgets('no on-device recognizer: Notes refuses to listen', timeout: timeout, (tester) async {
    await start(
      tester,
      voiceButton,
      overrides: [
        voiceRecognizerProvider.overrideWithValue(
          StopLateVoice(availability: VoiceAvailability.notOnDevice),
        ),
      ],
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    expect(find.byKey(const Key('voice_unavailable')), findsOneWidget);
    expect(find.textContaining('only transcribe speech online'), findsOneWidget);
    expect(find.byTooltip('Start listening'), findsNothing);
    await finish(tester, phone);
  });

  testWidgets('exporting all notes asks for the lock when some are locked', timeout: timeout, (
    tester,
  ) async {
    final lock = FakeLock(false);
    await start(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) =>
              TextButton(onPressed: () => showExportSheet(context), child: const Text('export')),
        ),
      ),
      overrides: [noteLockAuthenticatorProvider.overrideWithValue(lock)],
    );
    await tester.runAsync(() => phone.repo.createNote(title: 'Bank', body: 'pin', locked: true));
    await tester.tap(find.text('export'));
    await settle(tester);
    await tester.tap(find.text('Markdown'));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(lock.asked, 1);
    expect(find.textContaining('Not exported'), findsOneWidget);
    await finish(tester, phone);
  });
}
