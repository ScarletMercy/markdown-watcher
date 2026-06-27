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
/// started once. **We deliberately do NOT close it in [dispose]** — closing a
/// shared singleton from one widget's teardown would break any other widget
/// (or a future remount) still relying on it, and InAppLocalhostServer is not
/// idempotently restartable. [start] is itself guarded by the server's own
/// internal state and is safe to call again.
class PreviewWidget extends ConsumerStatefulWidget {
  const PreviewWidget({super.key});

  @override
  ConsumerState<PreviewWidget> createState() => _PreviewWidgetState();
}

class _PreviewWidgetState extends ConsumerState<PreviewWidget> {
  // Singleton server — shared across the app lifetime (see class docs).
  static final _server = InAppLocalhostServer(documentRoot: 'assets/preview');

  WebViewBridge? _bridge;
  bool _serverReady = false;
  bool _pageLoaded = false;
  String? _error;

  final _debouncer = Debouncer(const Duration(milliseconds: 400));

  @override
  void initState() {
    super.initState();
    // Timeout + catchError so a server-start failure (e.g. missing INTERNET
    // permission in release) surfaces instead of hanging. Mirrors the probe.
    _server.start().timeout(const Duration(seconds: 10)).then((_) {
      if (mounted) setState(() => _serverReady = true);
    }).catchError((Object e) {
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
    // Watch editor text; debounce a re-render whenever it changes.
    // ref.listen fires on every change (incl. the first build) without
    // returning a value into the widget tree.
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
