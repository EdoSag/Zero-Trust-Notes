import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_notes/l10n/l10n.dart';
import 'package:zt_assist/zt_assist.dart';

import '../../shared/text_direction.dart';
import 'note_assist.dart';

/// Lets the user pick what ZT Assist should do with [text], shows the
/// answer as it is written, and returns what to do with it, or null.
///
/// [selection] says that [text] is the part of the note the user selected.
/// A [checklist] note can be summarized and titled, not rewritten: its
/// lines are items, not prose.
Future<NoteAssistResult?> showNoteAssistSheet(
  BuildContext context, {
  required String text,
  bool selection = false,
  bool checklist = false,
}) => showModalBottomSheet<NoteAssistResult>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => NoteAssistSheet(text: text, selection: selection, checklist: checklist),
);

class NoteAssistSheet extends ConsumerStatefulWidget {
  const NoteAssistSheet({
    super.key,
    required this.text,
    this.selection = false,
    this.checklist = false,
  });

  final String text;
  final bool selection;
  final bool checklist;

  @override
  ConsumerState<NoteAssistSheet> createState() => _NoteAssistSheetState();
}

class _NoteAssistSheetState extends ConsumerState<NoteAssistSheet> {
  NoteAssistAction? _action;
  StreamSubscription<ZtAssistEvent>? _answering;
  String _answer = '';
  ZtAssistDone? _done;
  ZtAssistError? _error;
  bool _stoppedHere = false;

  bool get _running => _answering != null;

  @override
  void dispose() {
    // Leaving in the middle tells the model to stop writing.
    unawaited(_answering?.cancel());
    super.dispose();
  }

  void _start(NoteAssistAction action) {
    setState(() {
      _action = action;
      _answer = '';
      _done = null;
      _error = null;
      _stoppedHere = false;
    });
    final vault = ref.read(vaultControllerProvider.notifier);
    _answering = ref
        .read(ztAssistProvider)
        .ask(ZtAssistRequest(task: action.task, text: widget.text))
        .listen(
          (event) {
            if (!mounted) return;
            // A long answer is not cut short by the app locking itself.
            vault.touch();
            setState(() {
              switch (event) {
                case ZtAssistChunk(:final text):
                  _answer += text;
                case ZtAssistDone():
                  _done = event;
              }
            });
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(
              () => _error = error is ZtAssistException ? error.error : ZtAssistError.failed,
            );
          },
          onDone: () {
            if (mounted) setState(() => _answering = null);
          },
        );
  }

  Future<void> _stop() async {
    final answering = _answering;
    if (answering == null) return;
    setState(() {
      _answering = null;
      _stoppedHere = true;
    });
    await answering.cancel();
  }

  void _back() => setState(() {
    _action = null;
    _answer = '';
    _done = null;
    _error = null;
    _stoppedHere = false;
  });

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _answer.trim()));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(context.l10n.textCopied), duration: const Duration(seconds: 3)),
    );
  }

  void _use(NoteAssistApply apply) {
    final text = apply == NoteAssistApply.title ? tidyAssistTitle(_answer) : _answer.trim();
    Navigator.of(context).pop(NoteAssistResult(apply, text));
  }

  String _errorText(AppL10n l10n, ZtAssistError error) => switch (error) {
    ZtAssistError.notInstalled => l10n.assistNotInstalled,
    ZtAssistError.noModel => l10n.assistNoModel,
    ZtAssistError.loadFailed => l10n.assistLoadFailed,
    ZtAssistError.needsUpdate => l10n.assistNeedsUpdate,
    ZtAssistError.stopped => l10n.assistStopped,
    ZtAssistError.failed => l10n.assistFailed,
  };

  String _actionLabel(AppL10n l10n, NoteAssistAction action) => switch (action) {
    NoteAssistAction.summarize => l10n.assistSummarize,
    NoteAssistAction.rewrite => l10n.assistRewrite,
    NoteAssistAction.proofread => l10n.assistProofread,
    NoteAssistAction.translate => l10n.assistTranslate,
    NoteAssistAction.title => l10n.assistTitle,
  };

  static IconData _actionIcon(NoteAssistAction action) => switch (action) {
    NoteAssistAction.summarize => Icons.short_text,
    NoteAssistAction.rewrite => Icons.auto_fix_high_outlined,
    NoteAssistAction.proofread => Icons.spellcheck,
    NoteAssistAction.translate => Icons.translate,
    NoteAssistAction.title => Icons.title,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final action = _action;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              action == null ? l10n.assistAsk : _actionLabel(l10n, action),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(l10n.assistPrivacy, style: theme.textTheme.bodySmall),
            if (widget.selection) ...[
              const SizedBox(height: 4),
              Text(
                l10n.assistOnSelection,
                key: const Key('assist_on_selection'),
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            if (action == null) ..._choices(l10n) else ..._answerViews(l10n, theme, action),
          ],
        ),
      ),
    );
  }

  List<Widget> _choices(AppL10n l10n) => [
    for (final action in NoteAssistAction.values)
      if (!widget.checklist || !action.transforms)
        ListTile(
          key: Key('assist_${action.name}'),
          contentPadding: EdgeInsets.zero,
          leading: Icon(_actionIcon(action)),
          title: Text(_actionLabel(l10n, action)),
          onTap: () => _start(action),
        ),
  ];

  List<Widget> _answerViews(AppL10n l10n, ThemeData theme, NoteAssistAction action) {
    final error = _error;
    final done = _done;
    final answer = _answer.trim();
    final hasAnswer = answer.isNotEmpty;
    // Only a whole answer may take the text's place: one that was stopped,
    // or that read just the beginning of a long text, would lose the rest.
    final whole = done != null && !done.stopped && !done.truncated && error == null;
    final roomForAnswer = MediaQuery.sizeOf(context).height * 0.4;
    return [
      if (_running && !hasAnswer)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(l10n.assistStarting, key: const Key('assist_starting')),
            ],
          ),
        ),
      if (hasAnswer)
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: roomForAnswer.clamp(96.0, double.infinity)),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outline),
              borderRadius: BorderRadius.circular(4),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: SelectableText(
                  answer,
                  key: const Key('assist_answer'),
                  textDirection: textDirectionOf(answer),
                ),
              ),
            ),
          ),
        ),
      if (error != null) ...[
        const SizedBox(height: 8),
        Text(
          _errorText(l10n, error),
          key: const Key('assist_error'),
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
        ),
      ],
      if (done != null && done.truncated) ...[
        const SizedBox(height: 8),
        Text(
          action.transforms ? l10n.assistTooLongToReplace : l10n.assistReadBeginning,
          key: const Key('assist_truncated'),
          style: theme.textTheme.bodySmall,
        ),
      ],
      if (_stoppedHere || (done != null && done.stopped)) ...[
        const SizedBox(height: 8),
        Text(l10n.assistStoppedByUser, style: theme.textTheme.bodySmall),
      ],
      const SizedBox(height: 12),
      if (_running)
        OutlinedButton.icon(
          key: const Key('assist_stop'),
          onPressed: _stop,
          icon: const Icon(Icons.stop),
          label: Text(l10n.assistStop),
        )
      else ...[
        if (hasAnswer) ...[
          // The suite's buttons are as wide as they are allowed to be, so
          // two share a row only inside Expanded.
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('assist_copy'),
                  onPressed: _copy,
                  icon: const Icon(Icons.copy_outlined),
                  label: Text(l10n.copyText),
                ),
              ),
              if (action != NoteAssistAction.title && !widget.checklist) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _primary(
                    action.transforms,
                    key: const Key('assist_append'),
                    onPressed: () => _use(NoteAssistApply.append),
                    icon: Icons.note_add_outlined,
                    label: l10n.addToNote,
                  ),
                ),
              ],
              if (action == NoteAssistAction.title) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('assist_use_title'),
                    onPressed: tidyAssistTitle(_answer).isEmpty
                        ? null
                        : () => _use(NoteAssistApply.title),
                    icon: const Icon(Icons.title),
                    label: Text(l10n.assistUseAsTitle),
                  ),
                ),
              ],
            ],
          ),
          if (action.transforms && !widget.checklist) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('assist_replace'),
              onPressed: whole ? () => _use(NoteAssistApply.replace) : null,
              icon: const Icon(Icons.find_replace),
              label: Text(widget.selection ? l10n.assistReplaceSelection : l10n.assistReplaceText),
            ),
          ],
          const SizedBox(height: 8),
        ],
        TextButton(
          key: const Key('assist_back'),
          onPressed: _back,
          child: Text(l10n.assistOtherAction),
        ),
      ],
    ];
  }

  /// "Add to note" is the main button for a summary, and the second one
  /// when the answer can also replace the text.
  Widget _primary(
    bool secondary, {
    required Key key,
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
  }) => secondary
      ? OutlinedButton.icon(key: key, onPressed: onPressed, icon: Icon(icon), label: Text(label))
      : FilledButton.icon(key: key, onPressed: onPressed, icon: Icon(icon), label: Text(label));
}
