import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'debouncer.dart';
import 'editor_screen.dart';
import 'editor_state.dart';
import 'saf_file_repository.dart';
import 'webview_bridge.dart';

/// Production entry point.
///
/// Runs [MarkdownNotesApp] under a [ProviderScope] that overrides
/// [fileRepositoryProvider] with a real [SafFileRepository] (the override seam
/// declared in editor_state.dart). Tests that need a fake repository construct
/// their own ProviderScope; see the editor-state / repository unit tests.
void main() => runApp(
      ProviderScope(
        overrides: [
          fileRepositoryProvider.overrideWithValue(SafFileRepository()),
        ],
        child: const MarkdownNotesApp(),
      ),
    );

/// Production root widget.
///
/// Hosts the [MaterialApp] over [EditorScreen] AND owns the **app-level
/// autosave listener**. The listener is deliberately placed here — above
/// [EditorScreen] — rather than inside EditorScreen: rotating the device
/// rebuilds the EditorScreen layout subtree (tabs ↔ split), and a listener
/// living there could be torn down mid-debounce and drop a save. At this level
/// the listener survives layout rebuilds for the lifetime of the app.
///
/// The listener watches [editorProvider] (whole state, since the guard needs
/// both `dirty` and `file`), debounces ~1.5s (longer than the preview's 400ms
/// — saving on every keystroke would thrash app-private storage and the SAF
/// conflict probe), and calls [SafFileRepository.write] only when
/// `state.dirty && state.file != null`. [SafFileRepository.write] is
/// best-effort and never throws, so the listener has no try/catch of its own.
class MarkdownNotesApp extends ConsumerStatefulWidget {
  const MarkdownNotesApp({super.key});

  @override
  ConsumerState<MarkdownNotesApp> createState() => _MarkdownNotesAppState();
}

class _MarkdownNotesAppState extends ConsumerState<MarkdownNotesApp> {
  /// Autosave debounce. 1.5s balances "don't lose more than a couple seconds
  /// of typing on a crash" against "don't write on every keystroke". Distinct
  /// from the preview's 400ms — preview lag is cheap to tolerate, disk/SAF IO
  /// is not.
  final _autosave = Debouncer(const Duration(milliseconds: 1500));

  @override
  void dispose() {
    _autosave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ref.listen (not ref.watch) so this widget does not rebuild on every
    // keystroke — only the debounced side-effect runs. fireImmediately: false
    // (default) means the initial empty EditorState does not trigger a save.
    ref.listen<EditorState>(editorProvider, (prev, next) {
      if (!next.dirty || next.file == null) return;
      final file = next.file!;
      final text = next.text;
      _autosave.run(() {
        // Read the repository lazily inside the debounced callback: cheap, and
        // keeps the closure valid even if the override were hot-reloaded.
        ref.read(fileRepositoryProvider).write(file.uri, text);
      });
    });
    return MaterialApp(home: const EditorScreen());
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Phase 0b probe — RETAINED AS A TEST FIXTURE, NOT run by main().
//
// `integration_test/render_probe_test.dart` does `pumpWidget(const MyApp())`
// and polls the `Key('status')` line for RENDER_DONE. That test is the Phase 0b
// 生死 gate and runs on the Android emulator in CI. Deleting MyApp/ProbePage
// would break it, so both are kept verbatim below. main() now runs the real
// editor (MarkdownNotesApp, above); MyApp is reached only via the test.
// ─────────────────────────────────────────────────────────────────────────────

/// Hardcoded Phase 0b probe sample: exercises bold, inline code, a ```js fence,
/// inline math `$E=mc^2$`, block math `$$...$$`, and a ```mermaid fence.
/// Each `$` is escaped as `\$` so Dart does not treat it as string interpolation.
const sample = '''# Phase 0b Probe

Some **bold** and `code`.

```js
const x = 1;
```

Inline math \$E=mc^2\$ and block:

\$\$\\int_0^1 x\\,dx\$\$

```mermaid
graph TD; A-->B
```
''';

/// Phase 0b probe entry — kept ONLY so `render_probe_test.dart`'s
/// `pumpWidget(const MyApp())` still compiles and renders ProbePage unchanged.
/// Production uses [MarkdownNotesApp] (see [main]).
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(home: ProbePage());
}

class ProbePage extends StatefulWidget {
  const ProbePage({super.key});
  @override
  State<ProbePage> createState() => _ProbePageState();
}

/// Self-diagnosing probe serving the preview bundle over a local HTTP server.
///
/// The `asset:///` scheme is NOT supported by flutter_inappwebview on Android
/// (net::ERR_UNKNOWN_URL_SCHEME) — confirmed in CI. So we use InAppLocalhostServer
/// to serve `assets/preview/` at http://localhost:8080/, which makes the
/// template's relative URLs (preview.js, katex/, mermaid/ + its chunks) resolve
/// correctly with proper MIME types (mime 2.0.0 maps .mjs/.js → text/javascript,
/// so Mermaid's dynamic ES-module import works).
class _ProbePageState extends State<ProbePage> {
  static final _server = InAppLocalhostServer(documentRoot: 'assets/preview');
  WebViewBridge? _bridge;
  String _status = 'starting-server';
  final List<String> _diag = [];
  Timer? _watchdog;
  bool _serverReady = false;

  void _add(String line) {
    _diag.add(line);
    debugPrint('[probe] $line');
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    // Timeout + catchError so a server-start failure (e.g. missing INTERNET
    // permission in release) surfaces on-device instead of hanging forever.
    _server
        .start()
        .timeout(const Duration(seconds: 10))
        .then((_) {
      if (mounted) setState(() => _serverReady = true);
    }).catchError((e) {
      debugPrint('[probe] server start failed: $e');
      if (mounted) setState(() => _status = 'SERVER-ERROR: $e');
    });
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _server.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Phase 0b Probe')),
        body: Column(children: [
          Padding(
              padding: const EdgeInsets.all(8),
              child: Text(_status, key: const Key('status'))),
          Expanded(
            child: _serverReady
                ? InAppWebView(
                    initialUrlRequest: URLRequest(
                        url: WebUri('http://localhost:8080/template.html')),
                    onWebViewCreated: (c) {
                      _bridge = WebViewBridge(c);
                      _add('webview-created');
                    },
                    onLoadStart: (c, url) => _add('loadstart url=$url'),
                    onLoadStop: (c, url) async {
                      _add('loadstop url=$url');
                      final bridge = _bridge;
                      if (bridge == null) {
                        _add('no-bridge-at-loadstop');
                        return;
                      }
                      await bridge.installDoneHandler();
                      bridge.onRenderDone = (outline) async {
                        _add('renderdone outline=${outline.length}');
                        final counts = await bridge.renderCounts();
                        _watchdog?.cancel();
                        setState(() => _status =
                            'RENDER_DONE mermaidSvg=${counts['mermaidSvg'] ?? 0} '
                            'hljs=${counts['hljs'] ?? 0} katex=${counts['katex'] ?? 0}');
                      };
                      await bridge.render(sample);
                      _add('render-called');
                      _watchdog?.cancel();
                      _watchdog = Timer(const Duration(seconds: 15), () {
                        if (!_status.startsWith('RENDER_DONE')) {
                          setState(() => _status =
                              'TIMEOUT diag=' + _diag.take(20).join(' | '));
                        }
                      });
                    },
                    onConsoleMessage: (c, m) =>
                        _add('console:${m.messageLevel}:${m.message}'),
                    onReceivedError: (c, r, e) => _add('err:${e.description}'),
                    onReceivedHttpError: (c, r, e) =>
                        _add('httperr:${e.statusCode}:${e.data}'),
                  )
                : const Center(child: Text('Starting local server...')),
          ),
        ]),
      );
}
