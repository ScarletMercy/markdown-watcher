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

class _ProbePageState extends State<ProbePage> {
  WebViewBridge? _bridge;
  String _status = 'loading';

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
              },
              onLoadStop: (c, _) async {
                final bridge = _bridge!;
                await bridge.installDoneHandler();
                bridge.onRenderDone = (_) async {
                  final counts = await bridge.renderCounts();
                  setState(() => _status =
                      'RENDER_DONE mermaidSvg=${counts['mermaidSvg'] ?? 0} '
                      'hljs=${counts['hljs'] ?? 0} katex=${counts['katex'] ?? 0}');
                };
                await bridge.render(sample);
              },
            ),
          ),
        ]),
      );
}
