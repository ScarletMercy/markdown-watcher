// app/integration_test/render_probe_test.dart
//
// The Phase 0b 生死 gate. Launches the probe app, waits for the WebView to
// finish rendering the hardcoded sample, and asserts that code highlighting,
// KaTeX math, AND Mermaid (rendered to <svg>) are all present in the DOM.
//
// This runs ONLY on a device/emulator (iOS simulator via the `ios-render` CI job,
// Android emulator via `android-render`). It cannot run headlessly locally.
//
// If `mermaidSvg` is 0 on iOS while the others pass, that isolates the
// Mermaid-under-file:// worker-import risk the design flagged (Phase 0b runbook).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:markdown_watcher/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('WebView renders code + KaTeX + Mermaid', (tester) async {
    await tester.pumpWidget(const MyApp());
    final statusFinder = find.byKey(const Key('status'));

    // Poll up to ~45s for the status line to flip to RENDER_DONE with counts.
    // IMPORTANT: use pump(), NOT pumpAndSettle() — InAppWebView continuously
    // schedules frames, so pumpAndSettle never settles and throws a timeout
    // (which crashes the test opaquely before any diagnostic prints).
    String text = 'loading';
    for (var i = 0; i < 90 && !text.startsWith('RENDER_DONE'); i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (statusFinder.evaluate().isNotEmpty) {
        final widget = tester.widget(statusFinder);
        text = widget is Text ? (widget.data ?? '') : '';
      }
    }

    // Always print the final status so the CI log shows exactly what happened
    // (the probe also debugPrints a [probe] trail: loadstop/console/renderdone).
    debugPrint('[test] FINAL STATUS: "$text"');

    expect(
      text,
      startsWith('RENDER_DONE'),
      reason: 'WebView never signaled render-done (status was: "$text")',
    );

    final mermaid = int.parse(RegExp(r'mermaidSvg=(\d+)').firstMatch(text)!.group(1)!);
    final hljs = int.parse(RegExp(r'hljs=(\d+)').firstMatch(text)!.group(1)!);
    final katex = int.parse(RegExp(r'katex=(\d+)').firstMatch(text)!.group(1)!);

    expect(hljs, greaterThan(0), reason: 'Code not highlighted (hljs missing in DOM). Status: "$text"');
    expect(katex, greaterThan(0), reason: 'KaTeX math not rendered (.katex missing in DOM). Status: "$text"');
    expect(
      mermaid,
      greaterThan(0),
      reason: 'Mermaid did not render to <svg> — lazy worker import likely '
          'failed on this platform. Status: "$text"',
    );
  });
}
