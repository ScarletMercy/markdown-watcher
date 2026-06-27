// app/test/editor_actions_test.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_watcher/editor_actions.dart';

void main() {
  group('wrapSelection', () {
    test('wraps selected text with prefix/suffix', () {
      final r = wrapSelection('hello world', TextRange(start: 0, end: 5), '**', '**');
      expect(r.text, '**hello** world');
      expect(r.selection.start, 2);
      expect(r.selection.end, 7);
    });
    test('no selection inserts placeholder and places cursor inside', () {
      final r = wrapSelection('abc', TextRange(start: 3, end: 3), '**', '**');
      expect(r.text, 'abc****');
      expect(r.selection.start, 5); // cursor between the ** **? -> between placeholder
    });
  });
  group('toggleLinePrefix', () {
    test('adds "- " to start of line at cursor', () {
      final r = toggleLinePrefix('line1\nline2', TextRange(start: 6, end: 6), '- ');
      expect(r.text, 'line1\n- line2');
    });
  });
}
