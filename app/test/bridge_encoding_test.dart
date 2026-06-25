import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_watcher/bridge_encoding.dart';

void main() {
  group('buildRenderSource injection safety', () {
    test('produces a call with exactly two arguments', () {
      final src = buildRenderSource('hello', theme: 'dark');
      expect(src, startsWith('window.__render__('));
      expect(src.endsWith(')'), isTrue);
      // Strip "window.__render__(" prefix and trailing ")".
      final args = src.substring('window.__render__('.length, src.length - 1);
      // Exactly one top-level comma separates the two JSON literals.
      // (JSON string literals never contain an unquoted ',' at depth 0.)
      expect(_topLevelCommas(args), 1);
    });

    test('wraps markdown as a single JSON string literal that round-trips', () {
      final src = buildRenderSource('hello', theme: 'dark');
      final args = src.substring('window.__render__('.length, src.length - 1);
      final mdLiteral = args.substring(0, _endOfStringLiteral(args, 0));
      expect(jsonDecode(mdLiteral), 'hello');
    });

    test('wraps theme as a single JSON string literal that round-trips', () {
      final src = buildRenderSource('hi', theme: 'midnight"evil');
      final args = src.substring('window.__render__('.length, src.length - 1);
      // Skip past the markdown literal, then ", " (comma + space).
      var i = _endOfStringLiteral(args, 0);
      expect(args[i], ',');
      i++; // comma
      while (args[i] == ' ') i++; // optional spaces
      final themeLiteral = args.substring(i, _endOfStringLiteral(args, i));
      expect(jsonDecode(themeLiteral), 'midnight"evil');
    });

    test('nasty markdown stays a single inert literal (no JS breakout)', () {
      // Backticks, template-literal `${...}`, single & double quotes,
      // </script>, newlines, and a bare closing paren — all classic injection
      // vectors for a naive string-concat bridge.
      const nasty = "a`b\${alert(1)}c'd\"e</script>f\\g\nh)i;j";
      final src = buildRenderSource(nasty);
      final args = src.substring('window.__render__('.length, src.length - 1);

      // The literal must JSON-decode back to EXACTLY the input.
      final mdEnd = _endOfStringLiteral(args, 0);
      final mdLiteral = args.substring(0, mdEnd);
      expect(jsonDecode(mdLiteral), nasty);

      // Exactly one comma at top level → the nasty string did not inject an
      // extra argument or terminate the call early.
      expect(_topLevelCommas(args), 1);

      // Everything after the second literal must be only whitespace (call
      // closes cleanly with `)` which we already stripped).
      var i = mdEnd;
      expect(args[i], ',');
      i++;
      while (args[i] == ' ') i++;
      final themeEnd = _endOfStringLiteral(args, i);
      expect(args.substring(themeEnd).trim(), '');
    });

    test('jsonEncode is what makes it safe: no raw backslash-quote breakout', () {
      // The whole point: the source must NOT contain an unescaped " inside the
      // markdown literal (jsonEncode escapes it as \"), so JS keeps parsing it
      // as one string. Verify by checking the literal re-parses and that no
      // sequence of ") or "; appears that would close the literal in raw JS.
      const input = 'x");alert("pwned';
      final src = buildRenderSource(input);
      final args = src.substring('window.__render__('.length, src.length - 1);
      final mdLiteral = args.substring(0, _endOfStringLiteral(args, 0));
      // Round-trip holds → the malicious close-quote was neutralized by escaping.
      expect(jsonDecode(mdLiteral), input);
      // And the literal contains no UNescaped double-quote beyond the delimiters.
      final inner = mdLiteral.substring(1, mdLiteral.length - 1);
      for (var i = 0; i < inner.length; i++) {
        if (inner[i] == '"') {
          // Must be preceded by an odd number of backslashes (escaped).
          var backslashes = 0;
          for (var j = i - 1; j >= 0 && inner[j] == '\\'; j--) backslashes++;
          expect(backslashes % 2, 1,
              reason: 'Unescaped " inside markdown literal at $i would break out');
        }
      }
    });

    test('buildRenderCountsSource is a static JS snippet (no user input)', () {
      final src = buildRenderCountsSource();
      expect(src.contains('document.querySelectorAll'), isTrue);
      // No string interpolation of external content.
      expect(src.contains('__render__'), isFalse);
    });
  });
}

/// Count commas in [s] that are at JSON "top level" (not inside any string
/// literal). Used to assert the call has exactly the expected arity regardless
/// of commas appearing inside the markdown content.
int _topLevelCommas(String s) {
  var count = 0;
  var i = 0;
  while (i < s.length) {
    final ch = s[i];
    if (ch == '"') {
      i = _endOfStringLiteral(s, i); // skip past the literal
      continue;
    }
    if (ch == ',') count++;
    i++;
  }
  return count;
}

/// Index *one past* the JSON string literal that starts at [start] (which must
/// point at the opening `"`). Handles `\"` and `\\` escapes per JSON rules.
int _endOfStringLiteral(String s, int start) {
  assert(s[start] == '"');
  var i = start + 1;
  while (i < s.length) {
    final ch = s[i];
    if (ch == '\\') {
      i += 2; // skip escaped char
      continue;
    }
    if (ch == '"') return i + 1;
    i++;
  }
  throw StateError('Unterminated string literal in: $s');
}
