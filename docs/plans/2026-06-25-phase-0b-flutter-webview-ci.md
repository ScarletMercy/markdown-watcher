# Phase 0b — Flutter WebView Integration + CI Rendering Verification Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a minimal Flutter app that loads the verified `preview/` JS bundle in a WebView and renders a sample containing code/KaTeX/Mermaid, then **verify the rendering生死 (incl. Mermaid under iOS `file://`) automatically in GitHub Actions** on iOS (macOS runner) and Android (ubuntu runner) — without needing local hardware.

**Architecture:** A minimal Flutter app under `app/` (sibling to `preview/`) hosts `flutter_inappwebview` loading `assets/preview/template.html`. A `WebViewBridge` calls `window.__render__(markdown, theme)` via `evaluateJavascript` with the markdown **JSON-encoded** (injection-safe), and installs a shim so the template's `window.__renderDone__` forwards to a Flutter `addJavaScriptHandler`. After render-done, the app queries its own WebView DOM (mermaid `<svg>` / `.hljs` / `.katex` counts) and surfaces them in a `Text` widget. An `integration_test` asserts those counts are non-zero — this is the生死 gate, run on CI simulators/emulators.

**Tech Stack:** Flutter (stable, pinned), `flutter_inappwebview ^6.1.5`, `flutter_riverpod ^3.3.2` (+ codegen, four-pack pinned), `integration_test` SDK, GitHub Actions (`subosito/flutter-action@v2`, `setup-java`, `reactivecircus/android-emulator-runner`). Pattern referenced from `Agolid/LocationHook/.github/workflows/build.yml`.

**Scope discipline (YAGNI):** This plan verifies the rendering approach only. Deferred to Phase 1: `MarkdownRenderer` abstraction / `NativeRenderer` fallback, Riverpod app state, real editor (`TextField`), file access (SAF/bookmark), themes UI, scroll-sync. Phase 0b ships a hardcoded-sample rendering probe + its CI verification.

**Environment caveats (from probe):**
- Flutter CLI is **slow on first run** in this Windows env (Dart snapshot compile; `flutter doctor` hung minutes). Implementers: write project files **manually** where possible (avoid `flutter create`'s slow first run); allow long timeouts (≥300s) for `flutter pub get`/`analyze`/`test`; if a command hangs >10 min, stop and report.
- No local device/emulator → all runtime verification is **CI-only** (Tasks 5–6). Dart unit tests (Task 3) run locally via `flutter test` (no device).

---

## Task 1: Flutter app scaffold under `app/` + pinned deps + vendored assets

**Files:**
- Create: `app/pubspec.yaml`
- Create: `app/.gitignore`
- Create: `app/lib/main.dart` (minimal, placeholder — filled in Task 2)
- Create: `app/assets/preview/` (populated by copying from `preview/` + vendored mermaid — see Step 3)

**Step 1: Create `app/pubspec.yaml`** (deps pinned per design §9; versions verified via context7/pub.dev in the design phase):
```yaml
name: markdown_watcher
description: Top-tier mobile Markdown editor — Phase 0b rendering probe
publish_to: none
version: 0.1.0

environment:
  sdk: ^3.6.0
  flutter: ">=3.27.0"

dependencies:
  flutter:
    sdk: flutter
  flutter_inappwebview: ^6.1.5
  flutter_riverpod: ^3.3.2
  riverpod_annotation: ^3.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
  riverpod_generator: ^3.0.0
  build_runner: ^2.4.0
  flutter_lints: ^5.0.0

flutter:
  uses-material-design: true
  assets:
    - assets/preview/
    - assets/preview/mermaid/
    - assets/preview/themes/
    - assets/preview/katex/
    - assets/preview/highlight/
```
> NOTE: before locking, the implementer MUST verify each version is current via context7/pub.dev (per project policy [[verify-flutter-apis]]); the values above are from the design's §9 matrix (verified 2026-06-25). If a newer stable exists, use it and note the change.

**Step 2: Create `app/.gitignore`**
```
build/
.dart_tool/
.flutter-plugins
.flutter-plugins-dependencies
.packages
.pub-cache/
.pub/
*.iml
.idea/
.vscode/
ephemeral/
```

**Step 3: Populate `app/assets/preview/`** from the verified `preview/` bundle. The `template.html` asset URLs are flat (`katex/katex.min.css`, `highlight/styles/github.min.css`, `themes/light.css`, `preview.js`, `mermaid/mermaid.esm.min.mjs`), so copy into that layout. Write a reproducible script `app/scripts/sync-preview-assets.sh` (or `.ps1`) that:
1. Runs `cd ../preview && npm run build` (produces `dist/preview.js`).
2. Copies into `app/assets/preview/`:
   - `preview/dist/preview.js` → `assets/preview/preview.js`
   - `preview/src/template.html` → `assets/preview/template.html`
   - `preview/src/themes/light.css` → `assets/preview/themes/light.css`
   - `preview/node_modules/katex/dist/katex.min.css` → `assets/preview/katex/katex.min.css`
   - `preview/node_modules/katex/dist/fonts/*` → `assets/preview/katex/fonts/` (and **rewrite the `url(fonts/...)` references in katex.min.css if needed** so they resolve under the flat layout — verify by opening the css)
   - `preview/node_modules/highlight.js/styles/github.min.css` → `assets/preview/highlight/styles/github.min.css`
   - `preview/node_modules/mermaid/dist/mermaid.esm.min.mjs` (+ any sibling `*.mjs` chunk files mermaid 11 dynamically imports) → `assets/preview/mermaid/`
3. List the copied tree so it's auditable.

> ⚠️ **Mermaid chunk files are the生死 surface.** Mermaid 11 lazy-imports worker/chunk `.mjs` files at runtime. Copy the **entire** `mermaid/dist/*.mjs` set, not just the entry. Whether these resolve under iOS WKWebView `file://` is exactly what Task 5 verifies. Document the file list in the script output.

**Step 4: Minimal `app/lib/main.dart`** (placeholder so `flutter analyze` has a target; filled in Task 2):
```dart
import 'package:flutter/material.dart';
void main() => runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('Phase 0b scaffold')))));
```

**Step 5: Verify locally (slow CLI — allow ≥300s):**
```bash
cd app && flutter pub get && flutter analyze --no-fatal-infos
```
Expected: pub get resolves; analyze passes (the placeholder is trivial). If `flutter pub get` reports a version conflict, resolve per the version-verification note in Step 1 (do NOT silently loosen pins).

**Step 6: Commit**
```bash
git add app/ preview/  # if the sync script lives under preview/, else just app/
git commit -m "feat(app): flutter scaffold + pinned deps + vendored preview assets"
```

---

## Task 2: `WebViewBridge` — load template, JSON-channel `__render__`, render-done shim

**Files:**
- Create: `app/lib/webview_bridge.dart`
- Modify: `app/lib/main.dart`

**Step 1: Implement `WebViewBridge`** (the injection-safe bridge — design §4/§8 "桥高发区"):
```dart
// app/lib/webview_bridge.dart
import 'dart:convert';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Callback fired when the WebView finishes a render, carrying the outline.
typedef RenderDoneCallback = void Function(List<Map<dynamic, dynamic>> outline);

/// Bridge between Flutter and the preview WebView.
///
/// Security (design §4): markdown is passed to the WebView by interpolating a
/// JSON-encoded literal into evaluateJavascript — JSON strings are self-delimiting
/// JS string literals, so user markdown can never break out into executable JS.
/// NEVER interpolate raw markdown.
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

  /// Render markdown in the preview. markdown is JSON-encoded → safe JS literal.
  Future<void> render(String markdown, {String theme = 'light'}) async {
    final mdLiteral = jsonEncode(markdown);     // safe JS string literal
    final themeLiteral = jsonEncode(theme);
    await _controller.evaluateJavascript(
      source: 'window.__render__($mdLiteral, $themeLiteral)',
    );
  }

  /// Query the rendered DOM for verification counts. Returns a JSON string the
  /// caller decodes. Used by the app to self-verify rendering (Task 4 / integration_test).
  Future<Map<String, int>> renderCounts() async {
    final raw = await _controller.evaluateJavascript(source: '''
      JSON.stringify({
        mermaidSvg: document.querySelectorAll('div.mermaid svg').length,
        hljs: document.querySelectorAll('.hljs').length,
        katex: document.querySelectorAll('.katex').length,
        headings: document.querySelectorAll('h1,h2,h3').length
      })
    ''');
    if (raw == null) return {};
    return (jsonDecode(raw.toString()) as Map).map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
  }
}
```

**Step 2: Minimal app that loads the template, renders a hardcoded sample, self-verifies.** Replace `app/lib/main.dart`:
```dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'webview_bridge.dart';

const sample = '''# Phase 0b Probe

Some **bold** and `code`.

```js
const x = 1;
```

Inline math $E=mc^2$ and block:

$$\\int_0^1 x\\,dx$$

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
  InAppWebViewController? _wc;
  late final WebViewBridge _bridge;
  String _status = 'loading';

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Phase 0b Probe')),
        body: Column(children: [
          Padding(padding: const EdgeInsets.all(8), child: Text(_status, key: const Key('status'))),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri('about:blank')),
              initialSettings: InAppWebViewSettings(
                allowFileReadFromFileURLs: true,   // needed for local asset loading
                allowUniversalAccessFromFileURLs: true,
              ),
              onWebViewCreated: (c) { _wc = c; _bridge = WebViewBridge(c); },
              onLoadStop: (c, _) async {
                await _bridge.installDoneHandler();
                _bridge.onRenderDone = (_) async {
                  final counts = await _bridge.renderCounts();
                  // Surface counts as visible text for integration_test to assert.
                  setState(() => _status =
                      'RENDER_DONE mermaidSvg=${counts['mermaidSvg'] ?? 0} '
                      'hljs=${counts['hljs'] ?? 0} katex=${counts['katex'] ?? 0}');
                };
                await _bridge.render(sample);
              },
            ),
          ),
        ]),
      );
}
```
> NOTE on asset loading: `flutter_inappwebview` serves `assets/` via a special scheme (`flutter_assets`). Loading `assets/preview/template.html` is done by setting `initialUrlRequest` to the asset path or via `onLoadStop`+`loadUrl`. The implementer must get the local-asset URL right for flutter_inappwebview v6 (it differs from webview_flutter) — verify via the inappwebview docs (context7) and adjust. The `about:blank` + loadString approach is an alternative if direct asset URL is problematic. **This is a known fiddle point — iterate until the template loads and `__render__` executes.**

**Step 3: Verify locally (analyze only — running needs a device):**
```bash
cd app && flutter analyze --no-fatal-infos
```
Expected: analyzes clean (warnings OK). Running the app is deferred to CI (Task 5).

**Step 4: Commit**
```bash
git add app/lib/
git commit -m "feat(app): WebViewBridge + minimal probe page (JSON-channel render)"
```

---

## Task 3: Dart unit test — bridge JSON encoding is injection-safe

**Files:**
- Create: `app/test/webview_bridge_test.dart`

**Step 1: Failing test** (the bridge's `render` must produce an injection-safe JS call; we test the encoding by exposing the built source string):
```dart
// app/test/webview_bridge_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_watcher/webview_bridge.dart';

void main() {
  test('render source JSON-encodes markdown (quotes/backticks/script inert)', () {
    final nasty = '''text with `backticks`, "quotes", 'apos', </script>, \${alert(1)} and \\n''';
    final src = WebViewBridge.buildRenderSource(nasty, theme: 'dark');
    // The source must call __render__ with a single JSON string literal arg.
    expect(src, startsWith('window.__render__('));
    // No raw </script> or backtick-template escape possible:
    expect(src, isNot(contains('</script>')));   // jsonEncode escapes < ? -> actually it does NOT escape <
    // The key property: the arg parses as exactly one JSON string == nasty.
    final argStart = src.indexOf('(') + 1;
    final argEnd = src.indexOf(',', argStart);
    final literal = src.substring(argStart, argEnd);
    expect(_decode(literal), nasty);
  });
}

String _decode(String literal) => literal; // jsonDecode would decode; see note
```
> NOTE: refactor `WebViewBridge.render` to delegate to a **pure, testable** `static String buildRenderSource(String markdown, {String theme})` that constructs the `window.__render__(...)` source from `jsonEncode`. The test asserts the built source's first argument is a JSON literal that round-trips to the input — proving user markdown can't break the JS. (jsonEncode does not escape `<`, so a literal `</script>` inside an inline `<script>` WOULD be dangerous — but `evaluateJavascript` runs JS, not an HTML parser, so `</script>` is inert in this path. The test still pins that the arg is a well-formed single JSON literal; add an explicit assertion that the source contains no unescaped backtick that could close a JS template literal if you ever switch to template-string interpolation — which you must not.)

**Step 2: Refactor `WebViewBridge`** so `render()` calls `WebViewBridge.buildRenderSource(markdown, theme: theme)` and passes that to `evaluateJavascript`. This makes the encoding unit-testable without a WebView.

**Step 3: Run** — `cd app && flutter test test/webview_bridge_test.dart` (no device needed; flutter_test). Expected: PASS. Iterate until green.

**Step 4: Commit**
```bash
git add app/test/webview_bridge_test.dart app/lib/webview_bridge.dart
git commit -m "test(app): WebViewBridge JSON encoding is injection-safe"
```

---

## Task 4: `integration_test` — assert rendering in the real WebView

**Files:**
- Create: `app/integration_test/render_probe_test.dart`

**Step 1: Integration test** — launches the app, waits for the status `Text` to show `RENDER_DONE` with non-zero counts, then asserts. This is the生死 gate (if Mermaid doesn't render under iOS `file://`, `mermaidSvg` is 0 → fail).
```dart
// app/integration_test/render_probe_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:markdown_watcher/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('WebView renders code + KaTeX + Mermaid', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // Wait (up to ~30s) for the status line to report RENDER_DONE with real counts.
    Finder status = find.byKey(const Key('status'));
    String text = '';
    for (var i = 0; i < 60 && !text.startsWith('RENDER_DONE'); i++) {
      await tester.pump(const Duration(milliseconds: 500));
      final w = tester.widget<Text>(status);
      text = w.data ?? '';
    }
    expect(text, startsWith('RENDER_DONE'), reason: 'WebView never signaled render-done');
    // Parse counts out of the status string.
    final mermaid = RegExp(r'mermaidSvg=(\d+)').firstMatch(text)?.group(1);
    final hljs = RegExp(r'hljs=(\d+)').firstMatch(text)?.group(1);
    final katex = RegExp(r'katex=(\d+)').firstMatch(text)?.group(1);
    expect(int.parse(mermaid!), greaterThan(0), reason: 'Mermaid did not render to SVG (file:// worker import likely failed on this platform)');
    expect(int.parse(hljs!), greaterThan(0), reason: 'Code not highlighted');
    expect(int.parse(katex!), greaterThan(0), reason: 'KaTeX math not rendered');
  });
}
```

**Step 2: Cannot run locally (no device).** Static check only: `cd app && flutter analyze --no-fatal-infos`. Running happens in CI (Task 5).

**Step 3: Commit**
```bash
git add app/integration_test/
git commit -m "test(app): integration_test asserting WebView rendering (生死 gate)"
```

---

## Task 5: GitHub Actions workflow — Android (ubuntu) + iOS (macOS) verification

**Files:**
- Create: `.github/workflows/verify.yml`

**Step 1: The workflow.** Patterned after `Agolid/LocationHook/.github/workflows/build.yml` (subosito/flutter-action, setup-java, analyze, build), extended with an iOS job and `integration_test` on simulators/emulators.
```yaml
# .github/workflows/verify.yml
name: Verify Rendering

on:
  push:
    branches: [ main, 'phase-0b/**' ]
  pull_request:
  workflow_dispatch:

jobs:
  analyze-and-unit-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: 'temurin', java-version: '17', cache: 'gradle' }
      - uses: actions/setup-node@v4
        with: { node-version: '20', cache: 'npm', cache-dependency-path: preview/package-lock.json }
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.27.1', channel: 'stable', cache: true }
      - name: Build preview bundle
        run: cd preview && npm ci && npm run build
      - name: Sync preview assets into app
        run: bash app/scripts/sync-preview-assets.sh
      - name: Flutter pub get + analyze + unit tests
        run: |
          cd app
          flutter pub get
          flutter analyze --no-fatal-infos
          flutter test

  android-render:
    needs: analyze-and-unit-test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: 'temurin', java-version: '17', cache: 'gradle' }
      - uses: actions/setup-node@v4
        with: { node-version: '20', cache: 'npm', cache-dependency-path: preview/package-lock.json }
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.27.1', channel: 'stable', cache: true }
      - run: cd preview && npm ci && npm run build
      - run: bash app/scripts/sync-preview-assets.sh
      - name: Run integration_test on Android emulator
        uses: reactivecircus/android-emulator-runner@v2
        with:
          api-level: 33
          arch: x86_64
          script: cd app && flutter test integration_test/render_probe_test.dart

  ios-render:
    needs: analyze-and-unit-test
    runs-on: macos-14   # has Xcode + iOS simulator runtime
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20', cache: 'npm', cache-dependency-path: preview/package-lock.json }
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.27.1', channel: 'stable', cache: true }
      - run: cd preview && npm ci && npm run build
      - run: bash app/scripts/sync-preview-assets.sh
      - name: Run integration_test on iOS simulator
        run: |
          cd app
          flutter pub get
          cd ios && pod install && cd ..   # if needed; else skip
          flutter test integration_test/render_probe_test.dart -d "iPhone"
```
> NOTE: refine the iOS `-d` target and the `pod install` step against the actual simulator list (`xcrun simctl list`) once it runs; the mermaid SVG assertion in `render_probe_test.dart` is what makes this the生死 gate for the iOS `file://` worker-import risk. If `ios-render` fails specifically on `mermaidSvg=0` while Android passes, that isolates the iOS-WKWebView-file:// problem the design flagged.

**Step 2: Commit**
```bash
git add .github/workflows/verify.yml
git commit -m "ci: verify rendering on Android (ubuntu) + iOS (macos) simulators"
```

---

## Task 6: First CI run + Phase 0b verdict

**Step 1: Push + trigger.** The workflow needs a remote. If a GitHub remote exists, push; otherwise the user creates the repo + remote (out of scope to do blind). Once pushed, the `verify` workflow runs on push/PR.

**Step 2: Read CI results.** For each job:
- `analyze-and-unit-test` green → Dart side sound, bridge injection-safe (Task 3), preview bundle builds.
- `android-render` green → WebView + JS channel + KaTeX + hljs + **mermaid** all render on Android Chromium WebView.
- `ios-render` green → **the生死: WebView approach works on iOS WKWebView, incl. mermaid's dynamic worker import under `file://`.** 🎯

**Step 3: Write `app/docs/PHASE0B-VERDICT.md`** recording per-job pass/fail + the mermaid-svg counts per platform. Verdict:
- All green → **rendering approach validated end-to-end; proceed to Phase 1.**
- `ios-render` fails on mermaid → isolate: is it the worker `import()` under `file://`? → fallback per design (eager-bundle mermaid via esbuild, or Node-side render w/ DOM shim) → revise, re-run.
- `ios-render` fails broader → WebView loading/JS-channel issue on iOS → diagnose via CI logs.

**Step 4: Commit + tag**
```bash
git add app/docs/PHASE0B-VERDICT.md
git commit -m "docs(phase0b): CI rendering verification verdict"
git tag phase0b-verified   # only if all green
```

---

## Done criteria for this plan

- Flutter app under `app/` builds; `flutter analyze` clean; Dart unit test (bridge injection-safety) green locally.
- `integration_test` present and correct (asserts mermaid/hljs/katex counts).
- `.github/workflows/verify.yml` runs `analyze + unit + integration_test` on **both** Android (ubuntu) and iOS (macos).
- **Phase 0b verdict recorded**: rendering生死 verified on iOS (incl. mermaid `file://`) — or a documented fallback decision if it fails.

## Known fiddle points / risks (for implementer)
1. **flutter_inappwebview v6 local-asset URL** — get the template loading right (asset scheme vs loadString); iterate.
2. **Mermaid worker chunk resolution under `file://`** — the #1生死 risk; the iOS integration_test is the probe. If it fails, that's the expected signal, not a bug in this plan.
3. **KaTeX font `url()` rewriting** in the flat asset layout — verify fonts load (visual only; not asserted in integration_test — note as follow-up for the visual golden).
4. **Slow Flutter CLI locally** — write files manually, use long timeouts, don't block on local `flutter run`.

Next plan (Phase 1): `MarkdownRenderer` abstraction, Riverpod state, real editor, file access (SAF/bookmark — P0 b/c), themes, scroll-sync — once rendering is proven.
