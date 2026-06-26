# Phase 0 — Device Verification Runbook

> These checks need a **Mac (iOS)** and/or **Android device/emulator** plus the Flutter scaffold. They are out of reach on the Windows build box where the JS preview-bundle spine was built. Each is a **gate**; record pass/fail + evidence here as Phase 0b executes.

Prerequisite: the Flutter scaffold + `WebViewRenderer` integration (next plan, "Phase 0b"). The `preview/` bundle produced here is copied into `assets/preview/` (including `dist/preview.js`, `src/template.html`, `src/themes/light.css`, the katex/hljs CSS, and a vendored `mermaid/mermaid.esm.min.mjs`).

> ⚠️ **Phase 0b prerequisite — vendor Mermaid ESM explicitly (tracked, not a parenthetical).** `template.html` does `import('./mermaid/mermaid.esm.min.mjs')` but `src/mermaid/` does **not** exist in this repo (it's a deploy-time asset). Phase 0b must: vendor `mermaid@11.15.0` ESM into `assets/preview/mermaid/` **including its dynamically-imported worker chunks** (mermaid 11 pulls these at runtime), pin the version, and add a check that the import resolves. Because the Playwright golden never ran (browser binary blocked), this import path is **completely unexercised** — see P0(a) below.

> ⚠️ **The FIRST P0(a) probe must be Mermaid under iOS WKWebView `file://`.** Mermaid 11's dynamic `import()` of worker chunks may not resolve under `flutter_inappwebview`'s asset scheme / CSP. This is an **unverified生死 risk** hiding in a one-line `import()`. Probe it before investing in the rest of the integration. If it fails, the fallback (eager-bundle mermaid via esbuild, or render mermaid Node-side with a DOM shim) changes the architecture.

---

## P0(a) — iOS real-device WebView render生死  ⚠️ HIGHEST PRIORITY

**Why it's the生死 gate:** the entire hybrid architecture rests on `flutter_inappwebview` (6.1.5, last published 2024-10 — ~20 months stale). If it can't load local assets + run the JS bridge on current iOS, "top-tier display" is unachievable and the design must change.

**Setup:**
- Mac + Xcode + a physical iOS device or simulator.
- Flutter app with `flutter_inappwebview: ^6.1.5`, bundling `assets/preview/` (template + dist bundle + katex/hljs CSS + vendored mermaid ESM).
- Wire a JS bidirectional channel: Flutter calls `window.__render__(sample, theme)` via `evaluateJavascript(source:)` with the markdown **JSON-encoded** (never raw interpolation — see design §4 injection防护); register `__renderDone__` via `addJavaScriptHandler`.

**Pass criteria (all must hold):**
1. `template.html` loads from local assets (no remote fetch).
2. `__render__(sample)` renders: headings, table, task list, **highlighted code**, **KaTeX math** (inline + block), and **mermaid SVG**.
3. `__renderDone__` fires and returns a non-empty outline (h1/h2/h3 with source-line).
4. No console errors (capture via `onConsoleMessage`).
5. First-contentful paint within an acceptable budget (record ms).

**Fail → return to the design board** (evaluate `webview_flutter`, native `markdown_widget` for non-rich docs, or re-architect).

---

## P0(b) — iOS bookmark 5-scenario matrix

**Setup:** native plugin (Swift, `MethodChannel`) that picks a `.md` via `UIDocumentPickerViewController`, stores an `NSURL` security-scoped bookmark in the app's private storage, and resolves it on relaunch (wrapping access in `startAccessingSecurityScopedResource()`/`stop…`).

**Scenarios — record pass/fail + which of the 3 failure-branches triggered:**

1. Normal relaunch (app closed + reopened).
2. Kill-process relaunch (swipe-away, then reopen).
3. OS upgrade (major iOS version bump) then reopen.
4. File moved/renamed in Files app, then reopen.
5. iCloud-hosted file (ubiquitous) — confirm `ubiquitousItemDownloadingStatus` handling + bookmark validity.

**Failure branches to handle:** (a) `bookmarkDataIsStale == true` but resolvable → re-store new bookmark; (b) fully stale (moved/deleted) → re-prompt picker; (c) iCloud/file-provider — separate path.

---

## P0(c) — Android SAF best-effort write

**Setup:** Android emulator/device; `saf_util` + `saf_stream`; write via `ContentResolver.openOutputStream(uri, "wt")` (truncate-then-write, in place).

**Pass criteria:**
1. **URI never disappears mid-write** (concurrent reader sees old or new bytes, never a missing file) — verify by reading from another handle during write.
2. **`"wt"` truncates on the target provider** (behavior is provider-dependent — verify on ExternalStorageProvider + at least one OEM/cloud provider if feasible).
3. **`.bak` + byte-count check recover after a simulated mid-write crash** (kill the app mid-write, reopen, confirm `.bak` restoration path works and the truncated file is detected).
4. Confirm the conflict-check (mtime+size) fires when the file changed externally between load and save (note: SAF cloud URIs may return null mtime → defensive fallback to size+head/tail bytes).

---

## P0(d) device half — large-file open dual-threshold

**Setup:** synthetic `.md` files at the lower and upper thresholds (values TBD in Phase 0b; design suggests ~2 MB lower / ~10 MB upper, by bytes).

**Pass criteria:**
- File > lower threshold → opens **read-only** (editable disabled, preview works), with a warning.
- File > upper threshold → **refused** with a clear message.
- Confirm no OOM/hang at the threshold boundary (no virtualization in MVP).

---

## Notes
- The JS-bundle spine built here (29 tests, gzip within budget, injection-safe) is the **rendering half** of P0(a) and the entirety of P0(d)'s bundle size — both already verified. This runbook covers the **device** halves that need hardware.
- Run the **visual golden** (`UPDATE_GOLDENS=1 npm run test:e2e` after `playwright install chromium`) on an unrestricted machine as the qualitative top-tier gate before claiming P0(a) fully passed.

## CI verification (`.github/workflows/verify.yml` — Phase 0b)

The生死 checks P0(a)/(d) are automated in GitHub Actions: `analyze-and-unit-test` (ubuntu), `android-render` (ubuntu + Android emulator), `ios-render` (macos-14 + iOS simulator). The `render_probe_test.dart` integration_test asserts hljs / KaTeX / Mermaid-SVG counts > 0 in the real WebView. **Diagnosing the first red iOS run:**
- **All three counts 0 on iOS** → the preview bundle didn't load at all (the `asset:///` scheme + relative `<script src="preview.js">` failed under iOS WKWebView). Fallback: `InAppLocalhostServer(documentRoot: 'assets')` + an `http://localhost:8080/...` URL.
- **Only `mermaidSvg` is 0** (hljs + katex pass) → exactly the flagged risk: Mermaid's dynamic worker `import()` of `./chunks/*.mjs` failed under iOS `file://`. Fallback: eager-bundle mermaid via esbuild, or Node-side render with a DOM shim.
- **Android green, iOS red** → iOS-specific (WKWebView asset scheme / file://), not a shared bug.
