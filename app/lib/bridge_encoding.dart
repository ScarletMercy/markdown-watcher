import 'dart:convert';

/// Build the evaluateJavascript source for `window.__render__(markdown, theme)`.
/// Pure function (no Flutter deps) so the injection-safety property is unit-testable.
///
/// Security: markdown/theme are JSON-encoded into self-delimiting JS string
/// literals, so user content can never break out into executable JS.
String buildRenderSource(String markdown, {String theme = 'light'}) {
  final mdLiteral = jsonEncode(markdown);
  final themeLiteral = jsonEncode(theme);
  return 'window.__render__($mdLiteral, $themeLiteral)';
}

/// Build the evaluateJavascript source that queries rendered DOM counts.
String buildRenderCountsSource() {
  return '''
    JSON.stringify({
      mermaidSvg: document.querySelectorAll('div.mermaid svg').length,
      hljs: document.querySelectorAll('.hljs').length,
      katex: document.querySelectorAll('.katex').length,
      headings: document.querySelectorAll('h1,h2,h3').length
    })
  ''';
}
