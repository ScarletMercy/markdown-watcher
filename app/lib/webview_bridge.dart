import 'dart:convert';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'bridge_encoding.dart';

typedef RenderDoneCallback = void Function(List<Map<dynamic, dynamic>> outline);

/// Bridge between Flutter and the preview WebView.
class WebViewBridge {
  WebViewBridge(this._controller);
  final InAppWebViewController _controller;
  RenderDoneCallback? onRenderDone;

  /// Wire the template's `window.__renderDone__` to a Flutter handler.
  /// Call after the page has loaded (onLoadStop).
  Future<void> installDoneHandler() async {
    await _controller.evaluateJavascript(source: '''
      window.__renderDone__ = function(outline) {
        window.flutter_inappwebview.callHandler('renderDone', outline);
      };
    ''');
    _controller.addJavaScriptHandler(
      handlerName: 'renderDone',
      callback: (args) {
        final outline = (args.isNotEmpty ? args.first : []) as List;
        onRenderDone?.call(outline.cast<Map<dynamic, dynamic>>());
      },
    );
  }

  /// Render markdown. Delegates to the pure, tested buildRenderSource.
  Future<void> render(String markdown, {String theme = 'light'}) async {
    await _controller.evaluateJavascript(
        source: buildRenderSource(markdown, theme: theme));
  }

  /// Query rendered DOM counts for self-verification.
  Future<Map<String, int>> renderCounts() async {
    final raw =
        await _controller.evaluateJavascript(source: buildRenderCountsSource());
    if (raw == null) return {};
    return (jsonDecode(raw.toString()) as Map)
        .map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
  }
}
