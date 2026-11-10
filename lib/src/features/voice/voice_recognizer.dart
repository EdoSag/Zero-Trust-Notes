import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// A language the phone can recognise speech in.
class VoiceLanguage {
  const VoiceLanguage(this.id, this.name);

  /// The recognizer's id, such as `he_IL` (or `iw_IL` on older Android).
  final String id;
  final String name;

  /// Hebrew is listed under both its current and its old ISO code.
  bool get isHebrew {
    final lang = id.split(RegExp('[-_]')).first.toLowerCase();
    return lang == 'he' || lang == 'iw';
  }

  bool get isEnglish => id.toLowerCase().startsWith('en');
}

/// Why listening stopped early, in words for the person.
class VoiceError {
  const VoiceError(this.code);

  /// The recognizer's own code, such as `error_language_unavailable`.
  final String code;

  bool get languageMissing =>
      code.contains('language_unavailable') ||
      code.contains('language_not_supported') ||
      code.contains('server') ||
      code.contains('network');

  String message(String languageName) => switch (code) {
    _ when languageMissing =>
      'Speech recognition for $languageName isn\'t on this phone yet, and Notes only '
          'transcribes on the device. Download $languageName for offline speech in your '
          'phone\'s settings (search for "offline speech recognition"), then try again.',
    'error_permission' || 'error_insufficient_permissions' =>
      'Notes needs the microphone for voice notes. Allow it in your phone\'s settings.',
    'error_no_match' ||
    'error_speech_timeout' => 'Didn\'t catch that. Tap the microphone and try again.',
    'error_busy' || 'error_recognizer_busy' => 'Speech recognition is busy. Try again in a moment.',
    _ => 'Voice notes stopped ($code). Try again.',
  };
}

/// Whether voice notes can start.
enum VoiceAvailability {
  ready,

  /// The phone only has online speech recognition, which would send the
  /// voice to a server, so Notes won't use it.
  notOnDevice,

  /// No speech recognition at all, or the microphone is refused.
  unavailable,
}

/// Speech to text that never leaves the phone. Overridden in tests.
abstract interface class VoiceRecognizer {
  Future<VoiceAvailability> initialize();

  Future<List<VoiceLanguage>> languages();

  /// The phone's own language, if the recognizer has it.
  Future<String?> systemLanguageId();

  /// Listens until a pause or [stop]. [onText] gets the words so far (and
  /// `isFinal` at the end of the session); [onDone] runs when it stops.
  Future<void> listen({
    required String languageId,
    required void Function(String text, bool isFinal) onText,
    required void Function(VoiceError error) onError,
    required void Function() onDone,
  });

  Future<void> stop();

  Future<void> cancel();
}

final voiceRecognizerProvider = Provider<VoiceRecognizer>((ref) => OnDeviceVoiceRecognizer());

/// Android's (and iOS's) speech recognizer, kept on the device.
///
/// On iOS, `onDevice` makes recognition fail rather than go to a server.
/// On Android, speech_to_text only uses the on-device recognizer when the
/// phone has one (Android 12+); otherwise it quietly uses the default one,
/// which may be online. So on Android, Notes first asks the phone and
/// refuses to listen without an on-device recognizer.
class OnDeviceVoiceRecognizer implements VoiceRecognizer {
  static const _channel = MethodChannel('dev.sagron.zerotrustnotes/speech');

  final _speech = SpeechToText();
  void Function(VoiceError)? _onError;
  void Function()? _onDone;

  @override
  Future<VoiceAvailability> initialize() async {
    if (!kIsWeb && Platform.isAndroid) {
      bool onDevice;
      try {
        onDevice = await _channel.invokeMethod<bool>('onDeviceAvailable') ?? false;
      } on Object {
        onDevice = false;
      }
      if (!onDevice) return VoiceAvailability.notOnDevice;
    }
    final ok = await _speech.initialize(
      onError: (SpeechRecognitionError error) => _onError?.call(VoiceError(error.errorMsg)),
      onStatus: (status) {
        if (status == SpeechToText.doneStatus) _onDone?.call();
      },
    );
    return ok ? VoiceAvailability.ready : VoiceAvailability.unavailable;
  }

  @override
  Future<List<VoiceLanguage>> languages() async => [
    for (final locale in await _speech.locales()) VoiceLanguage(locale.localeId, locale.name),
  ];

  @override
  Future<String?> systemLanguageId() async => (await _speech.systemLocale())?.localeId;

  @override
  Future<void> listen({
    required String languageId,
    required void Function(String text, bool isFinal) onText,
    required void Function(VoiceError error) onError,
    required void Function() onDone,
  }) async {
    _onError = onError;
    _onDone = onDone;
    await _speech.listen(
      onResult: (result) => onText(result.recognizedWords, result.finalResult),
      listenOptions: SpeechListenOptions(
        localeId: languageId,
        onDevice: true,
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
        listenFor: const Duration(minutes: 2),
        pauseFor: const Duration(seconds: 5),
      ),
    );
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() => _speech.cancel();
}

/// The languages in the order people want them: the last one used, the
/// phone's own, Hebrew, English, then the rest by name.
List<VoiceLanguage> orderVoiceLanguages(
  List<VoiceLanguage> languages, {
  String? lastUsed,
  String? system,
}) {
  int rank(VoiceLanguage l) => l.id == lastUsed
      ? 0
      : l.id == system
      ? 1
      : l.isHebrew
      ? 2
      : l.isEnglish
      ? 3
      : 4;
  return [...languages]..sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    return byRank != 0 ? byRank : a.name.compareTo(b.name);
  });
}
