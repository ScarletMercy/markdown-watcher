// app/lib/editor_widget.dart
//
// Phase 1a Task 6 — the editor side of the split view: a monospace TextField
// plus a formatting toolbar (Bold/Italic/H1/H2/List/Code/Link).
//
// Reuse (do not reimplement):
//  - editor_actions.wrapSelection / toggleLinePrefix (return EditResult with the
//    new text + the TextRange the selection should become).
//  - editorProvider (Riverpod) as the source of truth for the buffer text.
//
// The controller is the bridge between user input and editorProvider: it is
// seeded once from provider state, forwards every keystroke to updateText, and
// is mutated by the toolbar (which then also pushes the result to the provider
// so the preview / dirty flag stay in sync).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'editor_actions.dart';
import 'editor_state.dart';

/// Markdown editor: a toolbar row over a multiline monospace [TextField].
///
/// State flow:
///  - The [TextEditingController] is two-way bound to `editorProvider.text`:
///    `ref.listen` in [build] pushes provider-side text changes (e.g. from
///    `loadFile`) into the controller. It fires once on first build, which also
///    serves as the initial seed. The `_controller.text == next` guard makes
///    controller-originated changes a no-op, breaking the onChanged → updateText
///    → listen feedback loop.
///  - User typing → [onChanged] → `editorProvider.updateText` (marks dirty).
///  - Toolbar tap → apply [wrapSelection] / [toggleLinePrefix], write the result
///    back into the controller (text + selection), then push to the provider.
class EditorWidget extends ConsumerStatefulWidget {
  const EditorWidget({super.key});

  @override
  ConsumerState<EditorWidget> createState() => _EditorWidgetState();
}

class _EditorWidgetState extends ConsumerState<EditorWidget> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    ref.read(editorProvider.notifier).updateText(value);
  }

  /// Apply an [EditResult] to the controller and push the new text to the
  /// provider, preserving the computed selection. `composing: TextRange.empty`
  /// prevents the IME from re-applying a stale composing region across the edit.
  void _apply(EditResult result) {
    // EditResult.selection is a TextRange; TextEditingController.copyWith
    // expects a TextSelection. Reconstruct with baseOffset/extentOffset so a
    // collapsed range becomes a collapsed selection (same caret position).
    _controller.value = _controller.value.copyWith(
      text: result.text,
      selection: TextSelection(
        baseOffset: result.selection.start,
        extentOffset: result.selection.end,
      ),
      composing: TextRange.empty,
    );
    ref.read(editorProvider.notifier).updateText(result.text);
    _focusNode.requestFocus();
  }

  void _bold() => _apply(wrapSelection(
        _controller.text,
        _controller.selection,
        '**',
        '**',
      ));

  void _italic() => _apply(wrapSelection(
        _controller.text,
        _controller.selection,
        '*',
        '*',
      ));

  void _code() => _apply(wrapSelection(
        _controller.text,
        _controller.selection,
        '`',
        '`',
      ));

  /// Inline link: wrap the selection (or a placeholder) with `[...]`(url).
  /// Collapsed cursor lands after `[` so the user can type link text.
  void _link() => _apply(wrapSelection(
        _controller.text,
        _controller.selection,
        '[',
        '](url)',
      ));

  void _h1() => _apply(toggleLinePrefix(
        _controller.text,
        _controller.selection,
        '# ',
      ));

  void _h2() => _apply(toggleLinePrefix(
        _controller.text,
        _controller.selection,
        '## ',
      ));

  void _list() => _apply(toggleLinePrefix(
        _controller.text,
        _controller.selection,
        '- ',
      ));

  @override
  Widget build(BuildContext context) {
    // Two-way bind the controller to `editorProvider.text`. In Riverpod 3.x,
    // `ref.listen` inside a ConsumerState's build() is the idiomatic place: it
    // auto-disposes and fires once on first build (giving the initial seed for
    // free), then again on every provider-side change (e.g. `loadFile`).
    //
    // The `_controller.text == next` guard makes controller-originated changes
    // a no-op, breaking the onChanged → updateText → listen feedback loop.
    ref.listen<String>(editorProvider.select((s) => s.text), (prev, next) {
      if (_controller.text == next) return;
      final sel = _controller.selection;
      _controller.value = TextEditingValue(
        text: next,
        selection: sel.copyWith(
          baseOffset: sel.baseOffset.clamp(0, next.length),
          extentOffset: sel.extentOffset.clamp(0, next.length),
        ),
      );
    });
    final theme = Theme.of(context);
    return Column(
      children: [
        // Formatting toolbar. Only the seven actions listed in the plan — YAGNI.
        Material(
          color: theme.colorScheme.surfaceContainerHighest,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _ToolbarButton(label: 'B', tooltip: 'Bold', onTap: _bold),
                _ToolbarButton(label: 'I', tooltip: 'Italic', onTap: _italic),
                _ToolbarButton(label: 'H1', tooltip: 'Heading 1', onTap: _h1),
                _ToolbarButton(label: 'H2', tooltip: 'Heading 2', onTap: _h2),
                _ToolbarButton(
                    label: '• —', tooltip: 'List item', onTap: _list),
                _ToolbarButton(
                    label: '< >', tooltip: 'Inline code', onTap: _code),
                _ToolbarButton(label: '🔗', tooltip: 'Link', onTap: _link),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            onChanged: _onChanged,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: TextStyle(
              fontFamily: 'RobotoMono',
              fontFamilyFallback: const ['monospace'],
              fontSize: 14,
              height: 1.4,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(12),
              isCollapsed: false,
            ),
          ),
        ),
      ],
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
