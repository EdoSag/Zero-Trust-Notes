import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../../shared/text_direction.dart';
import '../../shared/widgets/inline_button_style.dart';
import 'voice_recognizer.dart';

const _languagePreference = 'notes_voice_language';

/// Speak and it's written down, on the phone. Returns the text to add to
/// the note, or null if cancelled.
Future<String?> showVoiceNoteSheet(BuildContext context) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => const VoiceNoteSheet(),
);

class VoiceNoteSheet extends ConsumerStatefulWidget {
  const VoiceNoteSheet({super.key});

  @override
  ConsumerState<VoiceNoteSheet> createState() => _VoiceNoteSheetState();
}

enum _Phase { starting, unavailable, ready, listening }

class _VoiceNoteSheetState extends ConsumerState<VoiceNoteSheet> {
  late final VoiceRecognizer _recognizer = ref.read(voiceRecognizerProvider);
  _Phase _phase = _Phase.starting;
  List<VoiceLanguage> _languages = const [];
  VoiceLanguage? _language;

  /// Text from earlier listening sessions in this sheet.
  String _kept = '';

  /// What the current session has heard so far.
  String _live = '';
  String? _error;
  VoiceAvailability _availability = VoiceAvailability.ready;

  /// Counts listening sessions, so a late callback from an old one is
  /// ignored.
  int _session = 0;

  /// Stop was tapped; waiting for the recognizer's last words.
  bool _stopping = false;

  /// Completes when the current session ends.
  Completer<void>? _ending;

  String get _text => [_kept, _live].where((t) => t.trim().isNotEmpty).join(' ').trim();

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    if (_phase == _Phase.listening) _recognizer.cancel();
    _ending?.complete();
    super.dispose();
  }

  Future<void> _start() async {
    final vault = ref.read(vaultControllerProvider.notifier);
    VoiceAvailability availability;
    try {
      // The first time, Android asks for the microphone.
      availability = await vault.whileShowingSystemUi(_recognizer.initialize);
    } on Object {
      availability = VoiceAvailability.unavailable;
    }
    if (!mounted) return;
    if (availability != VoiceAvailability.ready) {
      setState(() {
        _phase = _Phase.unavailable;
        _availability = availability;
      });
      return;
    }
    final languages = await _recognizer.languages();
    final system = await _recognizer.systemLanguageId();
    final lastUsed = await ref.read(ztPreferencesStoreProvider).read(_languagePreference);
    if (!mounted) return;
    final ordered = orderVoiceLanguages(languages, lastUsed: lastUsed, system: system);
    setState(() {
      _languages = ordered;
      _language = ordered.firstOrNull;
      _phase = ordered.isEmpty ? _Phase.unavailable : _Phase.ready;
    });
    if (_phase == _Phase.ready) await _listen();
  }

  Future<void> _listen() async {
    final language = _language;
    if (language == null) return;
    final session = ++_session;
    setState(() {
      _phase = _Phase.listening;
      _stopping = false;
      _error = null;
      _live = '';
    });
    await _recognizer.listen(
      languageId: language.id,
      onText: (text, isFinal) {
        // Words after the session ended (or from an older one) are ignored,
        // so nothing is written down twice.
        if (!mounted || session != _session || _phase != _Phase.listening) return;
        setState(() => _live = text);
        if (isFinal) _finish(session);
      },
      onError: (error) {
        if (!mounted || session != _session || _phase != _Phase.listening) return;
        setState(() => _error = error.message(language.name));
        _finish(session);
      },
      onDone: () {
        if (!mounted) return;
        _finish(session);
      },
    );
  }

  /// Ends listening session [session], once: keeps what was heard and waits
  /// for the next tap.
  void _finish(int session) {
    if (session != _session || _phase != _Phase.listening) return;
    setState(_endSession);
    _ending?.complete();
    _ending = null;
  }

  void _endSession() {
    _kept = _text;
    _live = '';
    _phase = _Phase.ready;
    _stopping = false;
  }

  /// Asks the recognizer to stop and waits for its last words, which come
  /// after the stop. Gives up waiting after a few seconds.
  Future<void> _stopAndWait() async {
    if (_phase != _Phase.listening) return;
    final session = _session;
    final ending = _ending ??= Completer<void>();
    setState(() => _stopping = true);
    await _recognizer.stop();
    await ending.future.timeout(const Duration(seconds: 3), onTimeout: () {});
    if (mounted) _finish(session);
  }

  Future<void> _setLanguage(VoiceLanguage? language) async {
    if (language == null) return;
    if (_phase == _Phase.listening) await _recognizer.cancel();
    setState(() {
      _language = language;
      if (_phase == _Phase.listening) _endSession();
    });
    _ending?.complete();
    _ending = null;
    await ref.read(ztPreferencesStoreProvider).write(_languagePreference, language.id);
    await _listen();
  }

  Future<void> _done() async {
    await _stopAndWait();
    if (mounted) Navigator.of(context).pop(_text.isEmpty ? null : _text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final listening = _phase == _Phase.listening;
    final text = _text;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: Text('Voice note', style: theme.textTheme.titleLarge)),
            const SizedBox(height: 4),
            Text(
              'Transcribed on this phone. Your voice is never sent anywhere.',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            if (_phase == _Phase.unavailable)
              Text(
                _availability == VoiceAvailability.notOnDevice
                    ? 'This phone can only transcribe speech online, which would send your '
                          'voice to a server, so Notes doesn\'t use it. Voice notes need Android 12 '
                          'or later with on-device speech recognition.'
                    : 'Speech recognition isn\'t available on this phone, or the microphone isn\'t '
                          'allowed for Notes.',
                key: const Key('voice_unavailable'),
                style: theme.textTheme.bodyMedium,
              )
            else ...[
              if (_languages.isNotEmpty)
                DropdownButtonFormField<VoiceLanguage>(
                  key: const Key('voice_language'),
                  initialValue: _language,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Language',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final language in _languages)
                      DropdownMenuItem(value: language, child: Text(language.name)),
                  ],
                  onChanged: _setLanguage,
                ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 72, maxHeight: 220),
                child: SingleChildScrollView(
                  reverse: true,
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      text.isEmpty
                          ? (listening ? 'Listening…' : 'Tap the microphone and speak.')
                          : text,
                      textDirection: textDirectionOf(text),
                      style: text.isEmpty
                          ? theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)
                          : theme.textTheme.bodyLarge,
                    ),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: Text(_error!, style: TextStyle(color: scheme.error)),
                ),
              ],
              const SizedBox(height: 16),
              Center(
                child: _phase == _Phase.starting
                    ? const SizedBox.square(dimension: 64, child: CircularProgressIndicator())
                    : IconButton.filled(
                        iconSize: 36,
                        style: IconButton.styleFrom(
                          minimumSize: const Size.square(72),
                          backgroundColor: listening ? scheme.error : scheme.primary,
                          foregroundColor: listening ? scheme.onError : scheme.onPrimary,
                        ),
                        tooltip: listening ? 'Stop listening' : 'Start listening',
                        icon: Icon(listening ? Icons.stop : Icons.mic),
                        onPressed: listening ? (_stopping ? null : _stopAndWait) : _listen,
                      ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: inlineButtonStyle,
                  onPressed: text.isEmpty || _stopping ? null : _done,
                  child: const Text('Add to note'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
