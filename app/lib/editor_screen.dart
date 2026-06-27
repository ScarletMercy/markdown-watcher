// app/lib/editor_screen.dart
//
// Phase 1a Task 8 — adaptive host for the editor + preview.
//
// Layout policy (Material 3 breakpoints):
//  - Portrait / narrow (width < 600): a `DefaultTabController` + `TabBar` with
//    two tabs (编辑 / 预览) swiping between [EditorWidget] and [PreviewWidget].
//  - Landscape / wide (width >= 600): a side-by-side `Row` with a draggable
//    vertical split. The split ratio is held in State and clamped to [0.2, 0.8].
//
// Reuse (do not reimplement):
//  - [EditorWidget] / [PreviewWidget] are zero-arg `ConsumerStatefulWidget`s that
//    each read `editorProvider` themselves. EditorScreen therefore does NOT need
//    to be a ConsumerWidget / touch the provider — adding one would only create a
//    redundant read with no benefit (YAGNI).
//
// Out of scope (later tasks):
//  - Autosave listener                                       → Task 9 (main.dart, app-level)
//  - Bidirectional scroll-sync                              → Phase 1b
//
// The AppBar's "Open" and "Export" actions (Task 9) live at the bottom of this
// file; ProviderScope wiring + the autosave listener live in main.dart's
// MarkdownNotesApp.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'editor_state.dart';
import 'editor_widget.dart';
import 'preview_widget.dart';

/// Width (in logical px) at which we switch from portrait tabs to a split row.
///
/// 600 is the Material 3 / Flutter common tablet breakpoint (also matches the
/// `LayoutBreakpoint` guidance in the Material spec).
const double _kSplitBreakpoint = 600;

/// Title shown in the AppBar — the product's user-facing display name.
const String _kTitle = 'markdown笔记';

/// Adaptive host for the editor + preview.
///
/// Use [EditorScreen] directly as a `MaterialApp` home; it owns its own
/// [Scaffold] and [AppBar]. The portrait/landscape choice is recomputed on every
/// layout change via [LayoutBuilder], so rotating the device flips between the
/// tab and split layouts without extra plumbing.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  // Split ratio for the landscape row: fraction of the width given to the
  // editor (the preview gets the remainder). Clamped to [_kMinSplit, _kMaxSplit].
  static const double _kMinSplit = 0.2;
  static const double _kMaxSplit = 0.8;
  static const double _kInitialSplit = 0.5;

  double _split = _kInitialSplit;

  void _onDragUpdate(double totalDx, double totalWidth) {
    final next = (_split + totalDx / totalWidth).clamp(_kMinSplit, _kMaxSplit);
    setState(() => _split = next);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSplit = constraints.maxWidth >= _kSplitBreakpoint;
        // Keep an AppBar at the top in both layouts. The "Open"/"Export"
        // actions (Task 9) live in this AppBar — see [_OpenAction] /
        // [_ExportAction] at the bottom of the file.
        return Scaffold(
          appBar: AppBar(
            title: const Text(_kTitle),
            // `automaticallyImplyLeading` stays true so a future Navigator
            // back button works once the screen is hosted in a stack.
            //
            // The actions read/write providers, but EditorScreen itself is a
            // plain StatefulWidget (it doesn't otherwise need provider access).
            // Wrapping just the `actions` list in a [Consumer] is the lightest
            // way to obtain a `WidgetRef` here without converting the whole
            // screen to a ConsumerWidget — which would rebuild it on every
            // editorProvider change for no benefit (the editor/preview widgets
            // already watch the provider themselves).
            actions: const [
              _OpenAction(),
              _ExportAction(),
            ],
          ),
          body: isSplit
              ? _SplitBody(
                  split: _split,
                  onDragUpdate: _onDragUpdate,
                )
              : const _TabBody(),
        );
      },
    );
  }
}

/// Portrait layout: a two-tab swipe between editor and preview.
///
/// [DefaultTabController] is the simplest way to give the [TabBarView] a
/// controller without lifting state into the parent — and since the portrait
/// layout is rebuilt whenever width drops below the breakpoint, there's no need
/// for the controller to outlive a single portrait session.
class _TabBody extends StatelessWidget {
  const _TabBody();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 2,
      // TabBar needs an unbounded-height parent, so we stack it under the AppBar
      // via a Column inside the Scaffold body.
      child: Column(
        children: [
          TabBar(
            // Let the selected tab reflect the active theme's primary color
            // (works for both light and dark M3 schemes).
            labelColor: theme.colorScheme.primary,
            indicatorColor: theme.colorScheme.primary,
            tabs: const [
              Tab(text: '编辑'),
              Tab(text: '预览'),
            ],
          ),
          const Expanded(
            child: TabBarView(
              children: [
                EditorWidget(),
                PreviewWidget(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Landscape layout: editor | drag handle | preview, with an adjustable split.
///
/// The drag handle is a narrow vertical strip wrapping a centered grip. The
/// [GestureDetector.onHorizontalDragUpdate] reports the cumulative delta since
/// drag start; converting that to a fraction of the total width and adding it to
/// the starting ratio gives the new split. The clamping happens in
/// [_EditorScreenState._onDragUpdate].
class _SplitBody extends StatelessWidget {
  const _SplitBody({required this.split, required this.onDragUpdate});

  final double split;
  final void Function(double totalDx, double totalWidth) onDragUpdate;

  static const double _kHandleWidth = 8.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        // Subtract the handle width so the two Expanded panes split what's left.
        final paneWidth = totalWidth - _kHandleWidth;
        return Row(
          children: [
            SizedBox(
              width: paneWidth * split,
              child: const EditorWidget(),
            ),
            _DragHandle(
              width: _kHandleWidth,
              color: theme.dividerColor,
              onDragUpdate: (dx) => onDragUpdate(dx, paneWidth),
            ),
            SizedBox(
              width: paneWidth * (1 - split),
              child: const PreviewWidget(),
            ),
          ],
        );
      },
    );
  }
}

/// The vertical strip between the two panes. Draggable via a horizontal gesture.
class _DragHandle extends StatelessWidget {
  const _DragHandle({
    required this.width,
    required this.color,
    required this.onDragUpdate,
  });

  final double width;
  final Color color;
  final void Function(double dx) onDragUpdate;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => onDragUpdate(d.delta.dx),
        child: Container(
          width: width,
          color: color,
          alignment: Alignment.center,
          // A small centered grip so the affordance reads as "draggable".
          child: Container(
            width: 2,
            height: 36,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outline,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppBar actions (Task 9).
//
// These are StatelessWidget wrappers that lazily obtain a WidgetRef via a
// [Consumer] in build(), so the actions list can stay `const` and EditorScreen
// stays a plain StatefulWidget. Each action does a one-shot ref.read (or a
// short await) — none of them subscribe, so no rebuild concern.
// ─────────────────────────────────────────────────────────────────────────────

/// "Open" action: launches the SAF picker, reads the chosen file, and loads it
/// into [editorProvider]. [EditorWidget] reflects the new text via its own
/// `ref.listen` (Task 6), so no further wiring is needed here.
///
/// Cancellation (user backs out of the picker) returns null and is a no-op.
/// pickAndRead failures are surfaced via a [SnackBar] rather than thrown — the
/// repository itself never throws, but file_picker / SAF can still reject
/// (e.g. permission denied).
class _OpenAction extends StatelessWidget {
  const _OpenAction();

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) => IconButton(
        icon: const Icon(Icons.folder_open),
        tooltip: 'Open',
        onPressed: () => _pickAndLoad(context, ref),
      ),
    );
  }

  Future<void> _pickAndLoad(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(fileRepositoryProvider);
    final scaffold = ScaffoldMessenger.maybeOf(context);
    try {
      final file = await repo.pickAndRead();
      if (file == null) return; // user cancelled
      ref.read(editorProvider.notifier).loadFile(file);
    } catch (e) {
      // Defensive: the repository is best-effort, but a platform error here
      // (e.g. picker unavailable) should not crash the app.
      scaffold?.showSnackBar(SnackBar(content: Text('打开失败: $e')));
    }
  }
}

/// "Export" action: writes the current buffer to a real file in a user-chosen
/// directory via [FileRepository.saveAs]. This is the ONLY path that writes a
/// real file (autosave only mirrors to app-private storage — see
/// SafFileRepository). The suggested name falls back to 'note.md' when no file
/// is open yet. Best-effort: shows a SnackBar with the outcome.
class _ExportAction extends StatelessWidget {
  const _ExportAction();

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) => IconButton(
        icon: const Icon(Icons.ios_share),
        tooltip: 'Export',
        onPressed: () => _export(context, ref),
      ),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final state = ref.read(editorProvider);
    final repo = ref.read(fileRepositoryProvider);
    final scaffold = ScaffoldMessenger.maybeOf(context);
    // Allow exporting an empty buffer (the user may have cleared it on
    // purpose). Fall back to a generic name when nothing is open.
    final name = state.file?.name.isNotEmpty == true
        ? state.file!.name
        : 'note.md';
    try {
      final saved = await repo.saveAs(name, state.text);
      if (saved == null) return; // user cancelled the directory picker
      scaffold?.showSnackBar(SnackBar(content: Text('已导出: ${saved.name}')));
    } catch (e) {
      scaffold?.showSnackBar(SnackBar(content: Text('导出失败: $e')));
    }
  }
}
