import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'webview_bridge.dart';

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

void main() => runApp(const MyApp());

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

/// Self-diagnosing probe: every load/console/error event is appended to [_diag]
/// and debugPrint'd (so it shows in the CI log), and if render-done never fires
/// within 15s the status Text flips to "TIMEOUT diag=..." carrying the trail —
/// which the integration_test then surfaces on failure. This converts an opaque
/// "test failed" into "here's exactly what the WebView did".
class _ProbePageState extends State<ProbePage> {
  WebViewBridge? _bridge;
  String _status = 'loading';
  final List<String> _diag = [];
  Timer? _watchdog;

  void _add(String line) {
    _diag.add(line);
    debugPrint('[probe] $line');
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _watchdog?.cancel();
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
            child: InAppWebView(
              initialUrlRequest: URLRequest(
                  url: WebUri('asset:///assets/preview/template.html')),
              initialSettings: InAppWebViewSettings(
                allowFileAccessFromFileURLs: true,
                allowUniversalAccessFromFileURLs: true,
              ),
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
                // Watchdog: dump diagnostics if render-done never fires.
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
            ),
          ),
        ]),
      );
}
