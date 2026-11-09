/// Reduces a Markdown note body to a single-line plain-text snippet, for
/// contexts (list previews, search) that shouldn't show raw `**syntax**`.
/// Deliberately a cheap regex pass rather than a full parse — this only
/// needs to look reasonable in a truncated one-line preview, not round-trip.
String stripMarkdownForSnippet(String markdown) {
  var text = markdown
      .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
      .replaceAll(RegExp(r'`([^`]*)`'), r'$1')
      .replaceAll(RegExp(r'!\[([^\]]*)\]\([^)]*\)'), r'$1')
      .replaceAll(RegExp(r'\[([^\]]*)\]\([^)]*\)'), r'$1')
      .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*>\s?', multiLine: true), '')
      .replaceAll(RegExp(r'(\*\*|__)(.*?)\1'), r'$2')
      .replaceAll(RegExp(r'(\*|_)(.*?)\1'), r'$2')
      .replaceAll(RegExp(r'~~(.*?)~~'), r'$1');
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}
