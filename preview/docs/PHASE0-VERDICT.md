# Phase 0 Spine — Verdict

> Branch `phase-0` · tagged `phase0-spine` · 2026-06-25
> Scope: standalone JS preview bundle (`preview/`) — the rendering half of P0(a) + P0(d).

## What was built

A standalone, fully-testable JS preview bundle under `preview/` that renders markdown → HTML via markdown-it + KaTeX + highlight.js + Mermaid passthrough. It is the foundation for the Flutter WebView preview (will be copied verbatim into `assets/preview/`).

- `src/render.js` — markdown-it pipeline (texmath/KaTeX, footnote, anchor, hand-written task lists, data-source-line anchors, mermaid fence passthrough), `html:false`.
- `src/mermaid-cache.js` — source-hash cache deciding whether to (re)render a mermaid block.
- `src/template.html` — WebView shell: `window.__render__(text, theme)`, lazy in-browser mermaid import, `__renderDone__` completion handshake, outline callback.
- `src/themes/light.css` — typography-first theme (light + `data-theme="dark"` override).
- `src/entry.js` + `esbuild.config.js` — IIFE bundle → `dist/preview.js`.
- `scripts/measure-size.js` — gzip budget measurement.
- `e2e/` — Playwright visual goldens + a no-browser structural gate; `test/` — 29 unit/structural tests.

## Results (verified 2026-06-25)

| Gate | Result |
|---|---|
| Unit + structural tests | **29 pass / 0 fail** (`npm test`) |
| Build | ✅ `npm run build` → `dist/preview.js` |
| Injection invariants | ✅ locked (`html:false`, escape tests; raw `<script>`, `</script>` in code spans, template-literal payloads, U+2028 all inert) |
| P0(d) gzip budget | ✅ **520.4 KB gzip ≤ 600 KB** (~80 KB headroom); hljs-full dominates at ~307 KB gzip, `lib/common` would cut ~255 KB |
| Visual "top-tier" golden | ⏳ **Status (b): setup complete, pending browser binary** — Playwright chromium-1228 download blocked in the build sandbox; structural gate (no browser) green covering the full rendering surface. Run on an unrestricted machine to seed/eyeball goldens. |

## Bugs caught during build (and fixed)

Two real correctness bugs surfaced via the per-unit code reviews and were fixed before proceeding — both would have shipped silently:

1. **Task-list content drop (Unit 2, Critical):** re-tokenizing only the first inline child lost URLs/entities/code spans that `linkify` split into later children (`- [ ] see https://x.com now` → `see ` only). Fixed by slicing the marker off the first text token in place. Regression tests added.
2. **Mermaid fence closing-scan (Unit 3, Critical):** the scan broke on the first line starting with ```` ``` ````, corrupting mermaid blocks containing triple-backtick lines (code in node text). Fixed to mirror markdown-it's own fence rule (closing = marker + whitespace-only), plus EOF `state.line` fix, indentation guard, and tilde-fence support.

## Verdict

**The rendering pipeline is proven sound standalone.** The "top-tier display" stack (markdown-it + KaTeX + hljs + mermaid) renders correctly, is injection-safe, fits the gzip budget, and is fully unit-tested. The only unfinished gate is the **visual golden**, which is blocked solely by browser-binary availability in this sandbox — not by any code issue (the Playwright setup + structural gate are verified correct).

## What remains for Phase 0 (device-dependent, next plan — "Phase 0b")

These need a Mac (iOS) / Android device and the Flutter scaffold — out of reach on this Windows build box. See `PHASE0-DEVICE-RUNBOOK.md`:

- **P0(a) device half:** iOS real-device WebView render生死 (load `template.html`+bundle via `flutter_inappwebview`, JSON-channel `__render__`, confirm code/KaTeX/mermaid render + `__renderDone__` fires). **Gate: if it fails on iOS, the hybrid approach is dead — return to design.**
- **P0(b):** iOS bookmark 5-scenario real-device matrix.
- **P0(c):** Android SAF `openOutputStream("wt")` best-effort write + `.bak` recovery.
- **P0(d) device half:** large-file open dual-threshold (read-only > lower, reject > upper).

## Recommended next actions

1. Run the visual golden on an unrestricted machine: `node node_modules/playwright-core/cli.js install chromium && UPDATE_GOLDENS=1 npm run test:e2e` — then eyeball the screenshots (the qualitative top-tier gate).
2. Optional headroom: switch `highlight.js` → `highlight.js/lib/common` + on-demand `registerLanguage` (cuts ~255 KB gzip to ~265 KB total); add a test guarding against accidental full re-import.
3. Start Phase 0b: Flutter scaffold + `WebViewRenderer` integration + execute the device runbook.
