import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zt_assist/zt_assist.dart';

/// The way to ZT Assist, the AI that runs on this phone in its own app.
/// Tests put a fake here.
final ztAssistProvider = Provider<ZtAssist>((ref) => ZtAssist.instance);

/// Whether ZT Assist is on this phone. The editor offers "Ask ZT Assist"
/// only then. Nothing is started to find out.
final assistInstalledProvider = FutureProvider<bool>((ref) async {
  try {
    return await ref.watch(ztAssistProvider).isInstalled();
  } on Object {
    return false;
  }
});

/// What ZT Assist can do with a note.
enum NoteAssistAction {
  summarize(ZtAssistTask.summarize),
  rewrite(ZtAssistTask.rewrite),
  proofread(ZtAssistTask.proofread),
  translate(ZtAssistTask.translate),
  title(ZtAssistTask.title);

  const NoteAssistAction(this.task);

  final ZtAssistTask task;

  /// Whether the answer is the text itself in another form, so it can take
  /// the text's place.
  bool get transforms => switch (this) {
    rewrite || proofread || translate => true,
    summarize || title => false,
  };
}

/// Where an answer goes in the note.
enum NoteAssistApply {
  /// In place of the text that was read.
  replace,

  /// At the end of the note.
  append,

  /// As the note's title.
  title,
}

/// What the user chose to do with an answer.
class NoteAssistResult {
  const NoteAssistResult(this.apply, this.text);

  final NoteAssistApply apply;
  final String text;
}

/// A suggested title as a title: the first line, without the quotes, stars
/// or "Title:" a model likes to put around it.
String tidyAssistTitle(String answer) {
  final line = answer
      .split('\n')
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '');
  var title = line.replaceFirst(RegExp(r'^(title|כותרת)\s*[:：]\s*', caseSensitive: false), '');
  title = title.replaceAll(RegExp(r'^[#*_"“”״\s]+|[*_"“”״\s]+$'), '');
  return title;
}
