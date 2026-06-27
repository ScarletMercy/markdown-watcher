// app/lib/editor_state.dart
//
// Phase 1a Task 5 — Riverpod editor state (manual, no codegen).
//
// Holds the editor's reactive state: the open file, the in-buffer text, and the
// dirty flag. `fileRepositoryProvider` is an override seam — `main` overrides it
// with `SafFileRepository` (prod) or `InMemoryFileRepository` (test). The editor
// widgets (Task 6) and screen (Task 8/9) watch `editorProvider`.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'file_repository.dart';

/// Override seam for the file-access backend.
///
/// Throws by default so a missing override fails loudly rather than silently
/// resolving to a null repository. `main` overrides this with
/// `SafFileRepository` (prod) or `InMemoryFileRepository` (test).
final fileRepositoryProvider = Provider<FileRepository>((ref) {
  throw UnimplementedError(
    'override in main with SafFileRepository (prod) or '
    'InMemoryFileRepository (test)',
  );
});

/// Immutable snapshot of the editor: the loaded file, the current text, and
/// whether the buffer has unsaved changes.
class EditorState {
  final MarkdownFile? file;
  final String text;
  final bool dirty;

  EditorState({this.file, this.text = '', this.dirty = false});

  EditorState copy({MarkdownFile? file, String? text, bool? dirty}) =>
      EditorState(
        file: file ?? this.file,
        text: text ?? this.text,
        dirty: dirty ?? this.dirty,
      );
}

/// Manages the editor's state. Load a file to reset the buffer to its content;
/// mutate text on each keystroke, marking the buffer dirty.
class EditorNotifier extends Notifier<EditorState> {
  @override
  EditorState build() => EditorState();

  void loadFile(MarkdownFile f) =>
      state = state.copy(file: f, text: f.content, dirty: false);

  void updateText(String t) => state = state.copy(text: t, dirty: true);
}

final editorProvider =
    NotifierProvider<EditorNotifier, EditorState>(EditorNotifier.new);
