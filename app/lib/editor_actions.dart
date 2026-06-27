import 'package:flutter/widgets.dart';

/// Result of a toolbar text edit: the new full text and the [TextRange] the
/// editor's selection should be set to afterwards.
class EditResult {
  final String text;
  final TextRange selection;

  EditResult(this.text, this.selection);
}

/// Wraps the selection [sel] of [text] with [prefix] and [suffix].
///
/// When there is a non-empty selection, the selected run is wrapped and the
/// selection is kept on the (now-shifted) original content.
///
/// When the selection is collapsed (start == end), only prefix + suffix are
/// inserted and the cursor is placed right after the prefix, so the user can
/// immediately type the content to be wrapped.
EditResult wrapSelection(
  String text,
  TextRange sel,
  String prefix,
  String suffix,
) {
  final start = sel.start.clamp(0, text.length);
  final end = sel.end.clamp(0, text.length);

  if (start == end) {
    final newText = text.replaceRange(start, end, '$prefix$suffix');
    final cursor = start + prefix.length;
    return EditResult(newText, TextRange(start: cursor, end: cursor));
  }

  final selected = text.substring(start, end);
  final newText = text.replaceRange(start, end, '$prefix$selected$suffix');
  return EditResult(
    newText,
    TextRange(start: start + prefix.length, end: end + prefix.length),
  );
}

/// Toggles [prefix] at the start of the line containing the cursor [sel].
///
/// Currently adds the prefix (used for list items "- " and headings "# ").
/// The cursor is moved to follow the inserted prefix.
EditResult toggleLinePrefix(String text, TextRange sel, String prefix) {
  final i = sel.start.clamp(0, text.length);
  final lineStart = (i == 0) ? 0 : text.lastIndexOf('\n', i - 1) + 1;
  final newText = text.replaceRange(lineStart, lineStart, prefix);
  final cursor = i + prefix.length;
  return EditResult(newText, TextRange(start: cursor, end: cursor));
}
