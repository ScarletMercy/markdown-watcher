// app/lib/preview_widget.dart
//
// Phase 1a Task 6 — the preview side of the split view: renders the editor's
// markdown into the bundled preview page, served over a local HTTP server.
//
// Reuse (do not reimplement):
//  - InAppLocalhostServer (singleton) serves assets/preview at :8080.
//  - WebViewBridge.installDoneHandler / render / onRenderDone.
//  - Debouncer to coalesce rapid keystrokes before re-rendering.
//  - editorProvider as the markdown source.
//
// Injection-safe render path (bridge_encoding.dart) is unchanged — we only call
// WebViewBridge.render, which delegates to buildRenderSource.

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'debouncer.dart';
import 'editor_state.dart';
import 'webview_bridge.dart';

/// Renders the editor's markdown into a WebView, debouncing rapid edits.
///
/// The [InAppLocalhostServer] is a singleton: a `static final` instance is
/// started **at most once** across the app lifetime (gated by
/// [_serverStarted]). **We deliberately do NOT close it in [dispose]** —
/// closing a shared singleton from one widget's teardown would break any other
/// consumer, and InAppLocalhostServer is not idempotently restartable.
///
/// NOTE: `start()` is also NOT idempotent — calling it on an already-running
/// server throws "Server already started". So [initState] must not re-invoke
/// it when this widget rebuilds. Two defenses:
///   1. [AutomaticKeepAliveClientMixin] keeps this widget alive across
///      TabBarView tab switches, so initState normally runs only once.
///   2. [_serverStarted] (static) gates start() as a belt-and-suspenders guard
///      in case the widget is ever rebuilt (memory pressure, etc.).
class PreviewWidget extends ConsumerStatefulWidget {
  const PreviewWidget({super.key});

  @override
  ConsumerState<PreviewWidget> createState() => _PreviewWidgetState();
}

class _PreviewWidgetState extends ConsumerState<PreviewWidget>
    with AutomaticKeepAliveClientMixin {
  // Singleton server — shared across the app lifetime (see class docs).
  static final _server = InAppLocalhostServer(documentRoot: 'assets/preview');
  // start() throws "Server already started" on a second call, so gate it.
  // Static so it survives widget rebuilds.
  static bool _serverStarted = false;

  WebViewBridge? _bridge;
  bool _serverReady = false;
  bool _pageLoaded = false;
  String? _error;

  final _debouncer = Debouncer(const Duration(milliseconds: 400));

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _ensureServerStarted();
  }

  /// Start the singleton server at most once. On rebuild (e.g. returning to
  /// the preview tab), the server is already running — mark ready instead of
  /// calling start() again (which would throw "Server already started").
  void _ensureServerStarted() {
    if (_serverStarted) {
      if (mounted) setState(() => _serverReady = true);
      return;
    }
    _server
        .start()
        .timeout(const Duration(seconds: 10))
        .then((_) {
          _serverStarted = true;
          if (mounted) setState(() => _serverReady = true);
        })
        .catchError((Object e) {
          // Race guard: a second instance racing past the flag before the first
          // resolved hits "already started" — treat as success (server is up).
          if ('$e'.contains('already started')) {
            _serverStarted = true;
            if (mounted) setState(() => _serverReady = true);
            return;
          }
          debugPrint('[preview] server start failed: $e');
          if (mounted) setState(() => _error = 'Server error: $e');
        });
  }

  @override
  void dispose() {
    // Drop our render-done hook so a stale callback can't fire after dispose.
    if (_bridge != null) _bridge!.onRenderDone = null;
    _debouncer.dispose();
    // Intentionally NOT closing the singleton server here — see class docs.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin.
    // Watch editor text; debounce a re-render whenever it changes.
    ref.listen<String>(editorProvider.select((s) => s.text), (previous, next) {
      _scheduleRender(next);
    });

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_error!, style: const TextStyle(color: Colors.red)),
        ),
      );
    }
    if (!_serverReady) {
      return const Center(child: Text('Starting local server...'));
    }
    return InAppWebView(
      initialUrlRequest:
          URLRequest(url: WebUri('http://localhost:8080/template.html')),
      onWebViewCreated: (controller) {
        _bridge = WebViewBridge(controller);
      },
      onLoadStop: (controller, url) async {
        final bridge = _bridge;
        if (bridge == null) return;
        await bridge.installDoneHandler();
        // Render the current buffer as soon as the page is ready.
        setState(() => _pageLoaded = true);
        await bridge.render(ref.read(editorProvider).text);
      },
      onConsoleMessage: (_, m) => debugPrint('[preview] console: ${m.message}'),
      onReceivedError: (c, r, e) =>
          debugPrint('[preview] err: ${e.description}'),
      onReceivedHttpError: (c, r, e) =>
          debugPrint('[preview] httperr: ${e.statusCode}: ${e.data}'),
    );
  }

  void _scheduleRender(String text) {
    // Never render before the page has loaded — the bridge's evaluateJavascript
    // would run against a half-initialized DOM.
    if (_bridge == null || !_pageLoaded) return;
    _debouncer.run(() {
      final bridge = _bridge;
      if (bridge == null || !mounted || !_pageLoaded) return;
      bridge.render(text);
    });
  }
}
