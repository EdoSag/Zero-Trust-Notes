/// Reduces a Markdown note body to a single-line plain-text snippet, for
/// contexts (list previews, search) that shouldn't show raw `**syntax**`.
/// Deliberately a cheap regex pass rather than a full parse — this only
/// needs to look reasonable in a truncated one-line preview, not round-trip.
String stripMarkdownForSnippet(String markdown) {
  var text = markdown
      .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
      .replaceAllMapped(RegExp(r'`([^`]*)`'), (m) => m[1] ?? '')
      .replaceAllMapped(RegExp(r'!\[([^\]]*)\]\([^)]*\)'), (m) => m[1] ?? '')
      .replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m[1] ?? '')
      .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*>\s?', multiLine: true), '')
      .replaceAllMapped(RegExp(r'(\*\*|__)(.*?)\1'), (m) => m[2] ?? '')
      .replaceAllMapped(RegExp(r'(\*|_)(.*?)\1'), (m) => m[2] ?? '')
      .replaceAllMapped(RegExp(r'~~(.*?)~~'), (m) => m[1] ?? '');
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}
