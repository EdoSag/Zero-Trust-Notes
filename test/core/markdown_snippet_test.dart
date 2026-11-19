import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_notes/src/shared/markdown_snippet.dart';

void main() {
  test('a preview keeps the words and drops the Markdown marks', () {
    expect(stripMarkdownForSnippet('milk and **eggs**'), 'milk and eggs');
    expect(stripMarkdownForSnippet('_soft_ `code` ~~gone~~'), 'soft code gone');
    expect(stripMarkdownForSnippet('# Title\n- [site](https://example.com)'), 'Title site');
    expect(stripMarkdownForSnippet('costs \$2'), 'costs \$2');
  });
}
