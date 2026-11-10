import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_notes/src/features/voice/voice_recognizer.dart';

void main() {
  test('the last language used comes first, then the phone\'s, Hebrew and English', () {
    final ordered = orderVoiceLanguages(
      const [
        VoiceLanguage('fr_FR', 'French'),
        VoiceLanguage('en_US', 'English (US)'),
        VoiceLanguage('iw_IL', 'Hebrew'),
        VoiceLanguage('ar_EG', 'Arabic'),
      ],
      lastUsed: 'ar_EG',
      system: 'fr_FR',
    );
    expect(ordered.map((l) => l.id), ['ar_EG', 'fr_FR', 'iw_IL', 'en_US']);
  });

  test('Hebrew is recognised under both its codes', () {
    expect(const VoiceLanguage('he_IL', 'Hebrew').isHebrew, isTrue);
    expect(const VoiceLanguage('iw-IL', 'Hebrew').isHebrew, isTrue);
    expect(const VoiceLanguage('hi_IN', 'Hindi').isHebrew, isFalse);
  });

  test('a missing offline language says how to get it', () {
    const error = VoiceError('error_language_unavailable');
    expect(error.languageMissing, isTrue);
    expect(error.message('Hebrew'), contains('Download Hebrew for offline speech'));
  });
}
