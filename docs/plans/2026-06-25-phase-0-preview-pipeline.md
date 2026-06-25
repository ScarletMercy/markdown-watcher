# Phase 0 — Preview Rendering Pipeline (JS bundle) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build and verify the standalone JS preview bundle (markdown-it + KaTeX + highlight.js + Mermaid passthrough) that delivers "top-tier" rendering, fully testable on this machine — the biggest de-risk of the v4 design — plus a device verification runbook for the device-dependent P0 checks.

**Architecture:** A Node ESM project under `preview/` produces a single `preview.js` bundle + assets that will later be copied into Flutter `assets/preview/`. The rendering pipeline (`renderMarkdown`) is a pure function (text → HTML) unit-tested with `node:test`; data-source-line anchors, hand-written task lists, and a Mermaid hash-cache are modular. Visual regressions covered by Playwright. This bundle is reused as-is by the Flutter WebView (DRY), so validating it standalone validates the rendering half of P0(a).

**Tech Stack:** Node ESM, markdown-it 14.2 + plugins, KaTeX 0.17, highlight.js 11.11, Mermaid 11.15 (browser-side), esbuild (build), node:test (unit), Playwright (visual goldens). Production deps pinned exact per `docs/plans/2026-06-25-markdown-editor-design.md` §9; devDeps caret.

**Why this scope:** P0(a/b/c) device halves (iOS WebView render, iOS bookmark, Android SAF `"wt"`) need a Mac/Android device — out of reach on this Windows box. The JS bundle is 100% verifiable here, is the foundation for P0(a)'s rendering, and directly yields P0(d) (gzip sizes). Device checks are a runbook (Task 12).

**Non-goals (next plans):** Flutter project scaffold, `WebViewRenderer` integration, iOS bookmark plugin, SAF best-effort write, anchor scroll-sync wiring.

---

## Task 1: Scaffold `preview/` Node project + lock production deps

**Files:**
- Create: `preview/package.json`
- Create: `preview/.gitignore`

**Step 1: Create package.json**

```json
{
  "name": "markdown-watcher-preview",
  "private": true,
  "version": "0.0.0",
  "type": "module",
  "scripts": {
    "test": "node --test test/",
    "test:e2e": "playwright test",
    "build": "node esbuild.config.js",
    "size": "node scripts/measure-size.js"
  },
  "dependencies": {
    "highlight.js": "11.11.1",
    "katex": "0.17.0",
    "markdown-it": "14.2.0",
    "markdown-it-anchor": "9.2.0",
    "markdown-it-footnote": "4.0.0",
    "markdown-it-texmath": "1.0.0"
  },
  "devDependencies": {
    "esbuild": "^0.23.0",
    "@playwright/test": "^1.48.0"
  }
}
```

> Note: `markdown-it-task-lists` deliberately excluded (archived 2018) — hand-written in Task 4. `mermaid` is browser-side only, added in Task 8/template; not a Node dep.

**Step 2: Create `preview/.gitignore`**

```
node_modules/
dist/
playwright-report/
test-results/
```

**Step 3: Install**

Run: `cd preview && npm install`
Expected: installs without peer-dep errors. If `markdown-it-texmath@1.0.0` warns on `katex` peer, that's fine (we pass engine explicitly).

**Step 4: Verify versions installed match the lock**

Run: `npm ls --depth=0`
Expected: the 6 production deps at exactly the pinned versions.

**Step 5: Commit**

```bash
git add preview/package.json preview/package-lock.json preview/.gitignore
git commit -m "chore(preview): scaffold node project, lock markdown-it/katex/hljs"
```

---

## Task 2: `renderMarkdown` core — TDD

**Files:**
- Create: `preview/test/render.test.js`
- Create: `preview/src/render.js`

**Step 1: Write the failing test**

```js
// preview/test/render.test.js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { renderMarkdown } from '../src/render.js';

test('heading + paragraph + bold', () => {
  const html = renderMarkdown('# Title\n\nSome **bold** text.\n');
  assert.match(html, /<h1[^>]*>Title<\/h1>/);
  assert.match(html, /<strong>bold<\/strong>/);
});

test('unordered + ordered list', () => {
  const html = renderMarkdown('- a\n- b\n\n1. x\n2. y\n');
  assert.match(html, /<ul>/);
  assert.match(html, /<ol>/);
});

test('link + code span', () => {
  const html = renderMarkdown('[ex](https://e.com) and `code`\n');
  assert.match(html, /<a href="https:\/\/e\.com">ex<\/a>/);
  assert.match(html, /<code>code<\/code>/);
});

test('blockquote', () => {
  assert.match(renderMarkdown('> quoted\n'), /<blockquote>/);
});
```

**Step 2: Run — verify it fails**

Run: `cd preview && npm test`
Expected: FAIL — Cannot resolve `../src/render.js`.

**Step 3: Implement minimal core**

```js
// preview/src/render.js
import MarkdownIt from 'markdown-it';
import footnote from 'markdown-it-footnote';
import anchor from 'markdown-it-anchor';
import texmath from 'markdown-it-texmath';
import katex from 'katex';
import hljs from 'highlight.js';

const md = new MarkdownIt({
  html: false,        // SECURITY: no raw HTML (design §7)
  linkify: true,
  typographer: true,
  highlight(str, lang) {
    if (lang && hljs.getLanguage(lang)) {
      try {
        return '<pre class="hljs"><code>' +
          hljs.highlight(str, { language: lang }).value + '</code></pre>';
      } catch { /* fall through */ }
    }
    return '<pre class="hljs"><code>' + md.utils.escapeHtml(str) + '</code></pre>';
  },
})
  .use(texmath, { engine: katex, delimiters: 'dollars' })
  .use(footnote)
  .use(anchor, { permalink: anchor.permalink.headerLink() });

export function renderMarkdown(text) {
  return md.render(text);
}

export { md };
```

**Step 4: Run — verify pass**

Run: `cd preview && npm test`
Expected: PASS (4 tests).

**Step 5: Commit**

```bash
git add preview/src/render.js preview/test/render.test.js
git commit -m "feat(preview): markdown-it core render pipeline"
```

---

## Task 3: `data-source-line` anchors (for scroll-sync) — TDD

**Files:**
- Create: `preview/test/anchors.test.js`
- Modify: `preview/src/render.js` (add core ruler)

**Step 1: Failing test**

```js
// preview/test/anchors.test.js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { renderMarkdown } from '../src/render.js';

test('block open tags carry data-source-line', () => {
  const html = renderMarkdown('# H\n\npara\n\n- a\n- b\n');
  // heading on source line 0, paragraph line 2, list line 4
  assert.match(html, /<h1[^>]*data-source-line="0"/);
  assert.match(html, /<p[^>]*data-source-line="2"/);
  assert.match(html, /<ul[^>]*data-source-line="4"/);
});

test('tokens without map are skipped (no crash)', () => {
  // hr has no useful map in some configs — must not throw
  assert.doesNotThrow(() => renderMarkdown('---\n'));
});
```

**Step 2: Run — fails** (`npm test`): no `data-source-line` attributes yet.

**Step 3: Add core ruler to `render.js`** — insert before the `.use(anchor...)` chain or as a separate `.use()`:

```js
// after md is created, before export:
md.core.ruler.push('source_lines', (state) => {
  for (const tok of state.tokens) {
    if (tok.map && tok.nesting === 1) {           // opening block tokens only
      tok.attrSet('data-source-line', String(tok.map[0]));
    }
  }
});
```

> Known limitation (design §4): inline tokens have no `map`; tight lists' hidden `<p>` tokens are skipped. Block-level anchors suffice for scroll-sync. Document this in a code comment.

**Step 4: Run — pass** (`npm test`).

**Step 5: Commit**

```bash
git add preview/src/render.js preview/test/anchors.test.js
git commit -m "feat(preview): data-source-line anchors for scroll-sync"
```

---

## Task 4: Hand-written task lists (replace archived plugin) — TDD

**Files:**
- Create: `preview/test/tasklist.test.js`
- Create: `preview/src/tasklist.js`
- Modify: `preview/src/render.js` (`.use(taskList)`)

**Step 1: Failing test**

```js
// preview/test/tasklist.test.js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { renderMarkdown } from '../src/render.js';

test('unchecked task', () => {
  const html = renderMarkdown('- [ ] todo\n');
  assert.match(html, /<li[^>]*data-task=""[^>]*>/);
  assert.match(html, /<input[^>]*type="checkbox"[^>]*>/);
  assert.doesNotMatch(html, /data-checked=""/);
});

test('checked task', () => {
  const html = renderMarkdown('- [x] done\n');
  assert.match(html, /data-checked=""/);
});

test('checkbox marker text is removed', () => {
  const html = renderMarkdown('- [x] done\n');
  assert.doesNotMatch(html, /\[x\]/);
});
```

**Step 2: Run — fails.**

**Step 3: Implement minimal task-list plugin**

```js
// preview/src/tasklist.js
const MARKER = /^\[([ xX])\]\s+/;

export default function taskList(md) {
  md.core.ruler.after('inline', 'task_lists', (state) => {
    const t = state.tokens;
    for (let i = 2; i < t.length; i++) {
      const open = t[i - 2];
      if (open.type === 'list_item_open' && t[i].type === 'inline' && MARKER.test(t[i].content)) {
        const m = MARKER.exec(t[i].content);
        const checked = m[1].toLowerCase() === 'x';
        t[i].content = t[i].content.slice(m[0].length);
        // drop the leading text children that rendered the "[x] "
        while (t[i].children.length && !/^\[?[ xX\]\s?)?$/.test(t[i].children[0].content || '')) {
          // remove until marker consumed — see note
        }
        open.attrSet('data-task', '');
        if (checked) open.attrSet('data-checked', '');
        else open.attrSet('data-unchecked', '');
        // prepend checkbox into the item via a render rule override:
      }
    }
  });

  // Render a checkbox at the start of a task list_item_open
  const defaultListItemOpen = md.renderer.rules.list_item_open || ((tokens, idx, o, e, self) => self.renderToken(tokens, idx, o));
  md.renderer.rules.list_item_open = (tokens, idx, o, env, self) => {
    let out = defaultListItemOpen(tokens, idx, o, env, self);
    if (tokens[idx].attrGet('data-task') !== null) {
      const checked = tokens[idx].attrGet('data-checked') !== null;
      out = out.replace('<li', '<li'); // noop placeholder
      out += `<input type="checkbox" disabled${checked ? ' checked' : ''}> `;
    }
    return out;
  };
}
```

> Note: child-token stripping is fiddly — if the test "marker text is removed" fails, the clean fix is to set `t[i].content` AND rebuild `t[i].children` from the new content via `md.inline.parse(...)`. Iterate until the 3 tests pass; this is the expected TDD loop. Do NOT ship until all 3 pass.

**Step 4: Wire into render.js:** add `import taskList from './tasklist.js';` and `.use(taskList)` in the chain.

**Step 5: Run — pass** (`npm test`). Iterate on Step 3 if needed.

**Step 6: Commit**

```bash
git add preview/src/tasklist.js preview/src/render.js preview/test/tasklist.test.js
git commit -m "feat(preview): hand-written task-list rule (replaces archived plugin)"
```

---

## Task 5: Injection safety regression — TDD (CRITICAL)

**Files:**
- Create: `preview/test/injection.test.js`

**Step 1: Failing test (write first, it should already pass once Task 2 is in — this is a guard)**

```js
// preview/test/injection.test.js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { renderMarkdown } from '../src/render.js';

test('raw HTML is escaped, not executed (html:false)', () => {
  const html = renderMarkdown('<script>alert(1)</script>\n');
  assert.doesNotMatch(html, /<script>alert/);     // must be escaped text
  assert.match(html, /&lt;script&gt;/);
});

test('code span escapes closing script tag', () => {
  const html = renderMarkdown('`</script>`\n');
  assert.match(html, /&lt;\/script&gt;/);
  assert.doesNotMatch(html, /<\/script>/);
});

test('template-literal / backtick payloads are inert', () => {
  const html = renderMarkdown('`${alert(1)}`\n');
  assert.match(html, /alert\(1\)/);               // present as text
  assert.doesNotMatch(html, /<script/);
});

test('U+2028 line separator does not break rendering', () => {
  const html = renderMarkdown('a b\n');
  assert.match(html, /a/);
  assert.match(html, /b/);
});
```

**Step 2: Run** (`npm test`): should PASS already (markdown-it `html:false` + code escaping). This test exists to **lock** the invariant — if a future change re-enables `html:true` or raw pass-through, it fails loudly.

**Step 3: Commit**

```bash
git add preview/test/injection.test.js
git commit -m "test(preview): lock injection-safety invariants (html:false, escape)"
```

---

## Task 6: Mermaid passthrough + hash-cache module — TDD

> Mermaid SVG rendering needs a browser DOM; it runs WebView-side, not in Node. Here we (a) pass mermaid fences through as `<div class="mermaid">…</div>` and (b) unit-test the hash-cache logic that decides whether to re-render.

**Files:**
- Create: `preview/test/mermaid-cache.test.js`
- Create: `preview/src/mermaid-cache.js`
- Modify: `preview/src/render.js` (mermaid fence rule)

**Step 1: Failing test**

```js
// preview/test/mermaid-cache.test.js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { renderMarkdown } from '../src/render.js';
import { shouldRender } from '../src/mermaid-cache.js';

test('mermaid fence becomes a mermaid div', () => {
  const html = renderMarkdown('```mermaid\ngraph TD; A-->B\n```\n');
  assert.match(html, /<div class="mermaid"[^>]*>graph TD; A-->B<\/div>/);
});

test('cache skips unchanged source, renders changed', () => {
  const cache = new Map();
  assert.equal(shouldRender('id1', 'same', cache), true);   // first time
  assert.equal(shouldRender('id1', 'same', cache), false);  // unchanged
  assert.equal(shouldRender('id1', 'changed', cache), true);// changed
});
```

**Step 2: Run — fails.**

**Step 3a: Implement the cache**

```js
// preview/src/mermaid-cache.js
function hash(s) {
  let h = 5381;
  for (let i = 0; i < s.length; i++) h = ((h << 5) + h + s.charCodeAt(i)) | 0;
  return String(h);
}

// Returns true if the block should be (re)rendered.
export function shouldRender(id, source, cache) {
  const digest = hash(source);
  if (cache.get(id) === digest) return false;
  cache.set(id, digest);
  return true;
}
```

**Step 3b: Mermaid fence rule in render.js** (before the default `highlight`):

```js
md.block.ruler.before('fence', 'mermaid_fence', (state, startLine, endLine, silent) => {
  const start = state.bMarks[startLine] + state.tShift[startLine];
  const marker = state.src.slice(start, start + 3);
  if (marker !== '```') return false;
  const lang = state.src.slice(start + 3, start + 3 + 7).trim().slice(0, 7);
  if (!lang.startsWith('mermaid')) return false;
  if (silent) return true;
  // collect until closing fence
  let nextLine = startLine + 1;
  while (nextLine < endLine && !state.src.slice(state.bMarks[nextLine], state.bMarks[nextLine] + 3).startsWith('```')) nextLine++;
  const content = state.getLines(startLine + 1, nextLine, state.tShift[startLine], false).trim();
  const token = state.push('mermaid', 'div', 0);
  token.content = content;
  token.map = [startLine, nextLine];
  token.markup = '```';
  token.info = 'mermaid';
  state.line = nextLine + 1;
  return true;
}, { alt: [] });

md.renderer.rules.mermaid = (tokens, idx) =>
  `<div class="mermaid" data-source-line="${tokens[idx].map ? tokens[idx].map[0] : ''}">${md.utils.escapeHtml(tokens[idx].content)}</div>`;
```

**Step 4: Run — pass** (`npm test`). Iterate the block-ruler if the fence matching is off; verify `data-source-line` present.

**Step 5: Commit**

```bash
git add preview/src/mermaid-cache.js preview/src/render.js preview/test/mermaid-cache.test.js
git commit -m "feat(preview): mermaid passthrough + source-hash cache"
```

---

## Task 7: HTML template + light/dark themes

**Files:**
- Create: `preview/src/template.html`
- Create: `preview/src/themes/light.css`
- Create: `preview/src/themes/dark.css`

**Step 1: template.html** — the WebView shell. Loads bundled CSS/JS, exposes `window.__render__(text, theme)` which calls `renderMarkdown` + sets content + (browser-side) runs mermaid.

```html
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="stylesheet" href="katex/katex.min.css">
  <link rel="stylesheet" href="highlight/styles/github.min.css" id="hljs-theme">
  <link rel="stylesheet" href="themes/light.css" id="theme-css">
</head>
<body>
  <article id="content"></article>
  <!-- bundle -->
  <script src="preview.js"></script>
  <script>
    // mermaid loaded lazily on first mermaid block (design §4)
    let mermaidReady = null;
    async function ensureMermaid() {
      if (!mermaidReady) {
        mermaidReady = import('./mermaid/mermaid.esm.min.mjs').then(m => {
          m.default.initialize({ startOnLoad: false });
          return m.default;
        });
      }
      return mermaidReady;
    }
    const cache = new Map();
    async function __render__(text, theme) {
      document.documentElement.setAttribute('data-theme', theme || 'light');
      document.getElementById('content').innerHTML = window.renderMarkdown(text);
      // mermaid blocks
      const nodes = document.querySelectorAll('div.mermaid');
      if (nodes.length) {
        const mermaid = await ensureMermaid();
        nodes.forEach((n, i) => {
          if (window.shouldRender('m' + i, n.textContent, cache)) {
            n.removeAttribute('data-processed');
            n.setAttribute('data-source-line', n.getAttribute('data-source-line') || '');
          }
        });
        await mermaid.run({ nodes: Array.from(nodes) });
      }
      // notify Flutter: render complete + outline
      window.__renderDone__ && window.__renderDone__(collectOutline());
    }
    function collectOutline() {
      return Array.from(document.querySelectorAll('h1,h2,h3'))
        .map(h => ({ level: +h.tagName[1], text: h.textContent, line: +h.getAttribute('data-source-line') }));
    }
  </script>
</body>
</html>
```

**Step 2: light.css / dark.css** — typography-first (system font stack, comfortable line-height, code block styling). Keep minimal but polished; this is where "top-tier" lives.

```css
/* preview/src/themes/light.css */
:root { --fg:#1f2328; --bg:#ffffff; --code-bg:#f6f8fa; --link:#0969da; }
html[data-theme="dark"] { --fg:#e6edf3; --bg:#0d1117; --code-bg:#161b22; --link:#58a6ff; }
body { margin:0; padding:16px; background:var(--bg); color:var(--fg);
  font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",system-ui,sans-serif;
  line-height:1.6; font-size:16px; -webkit-font-smoothing:antialiased; }
article { max-width:720px; margin:0 auto; }
h1,h2,h3 { line-height:1.25; margin:1.4em 0 .5em; }
a { color:var(--link); }
pre.hljs { background:var(--code-bg); padding:12px; border-radius:8px; overflow:auto; }
code { font-family:"SFMono-Regular",ui-monospace,monospace; }
pre code { background:none; }
img { max-width:100%; height:auto; border-radius:8px; }
blockquote { border-left:3px solid var(--code-bg); margin:0; padding-left:1em; color:inherit; opacity:.85; }
table { border-collapse:collapse; } th,td { border:1px solid var(--code-bg); padding:6px 12px; }
```

(dark.css may simply reuse the `[data-theme="dark"]` overrides above; keep both files so themes are swappable.)

**Step 3: Commit**

```bash
git add preview/src/template.html preview/src/themes/
git commit -m "feat(preview): webview template + light/dark themes"
```

---

## Task 8: Build the bundle (esbuild) → `dist/preview.js`

**Files:**
- Create: `preview/esbuild.config.js`

**Step 1: Build script**

```js
// preview/esbuild.config.js
import esbuild from 'esbuild';
import { readFileSync } from 'node:fs';

const banner = `
window.renderMarkdown = (await import('markdown-it')).default;
`.trimStart(); // placeholder — see note

await esbuild.build({
  entryPoints: ['src/render.js'],
  bundle: true,
  format: 'iife',
  globalName: 'MWPreview',
  outfile: 'dist/preview.js',
  target: ['safari14', 'chrome90'],     // iOS WKWebView / Android Chromium
  minify: true,
  legalComments: 'none',
  define: { 'process.env.NODE_ENV': '"production"' },
});
console.log('built dist/preview.js');
```

> Note: the bundle must expose `window.renderMarkdown` and `window.shouldRender` for `template.html`. After the esbuild build, either (a) add a tiny `src/entry.js` that does `import {renderMarkdown} from './render.js'; import {shouldRender} from './mermaid-cache.js'; window.renderMarkdown = renderMarkdown; window.shouldRender = shouldRender;` and set `entryPoints:['src/entry.js']`, or (b) post-process. Use approach (a): create `preview/src/entry.js` and point esbuild at it. Update `entryPoints` accordingly.

**Step 2: Create `preview/src/entry.js`**

```js
import { renderMarkdown } from './render.js';
import { shouldRender } from './mermaid-cache.js';
window.renderMarkdown = renderMarkdown;
window.shouldRender = shouldRender;
```

**Step 3: Set entryPoints to `src/entry.js`** in esbuild.config.js, remove the placeholder banner.

**Step 4: Build + sanity check**

Run: `cd preview && npm run build`
Expected: writes `dist/preview.js`; `node -e "require('./dist/preview.js')"` may fail (browser globals) — instead verify in Task 10 via Playwright.

**Step 5: Commit**

```bash
git add preview/esbuild.config.js preview/src/entry.js
git commit -m "build(preview): esbuild bundle to dist/preview.js"
```

---

## Task 9: gzip size measurement → P0(d) verdict + thresholds

**Files:**
- Create: `preview/scripts/measure-size.js`
- Create: `preview/docs/SIZE-REPORT.md` (generated; commit a snapshot)

**Step 1: Measure script** (no extra dep — use Node zlib)

```js
// preview/scripts/measure-size.js
import { gzipSync } from 'node:zlib';
import { statSync, readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

function sizeGz(p) { return gzipSync(readFileSync(p)).length; }
function sizeRaw(p) { return statSync(p).size; }

const groups = {
  'dist/preview.js (markdown-it+katex+hljs bundle)': ['dist/preview.js'],
  'katex css+fonts': listDir('node_modules/katex/dist', ['katex.min.css']),
  'highlight theme': ['node_modules/highlight.js/styles/github.min.css'],
  'themes': ['src/themes/light.css', 'src/themes/dark.css'],
};
function listDir(dir, files) { return files.map(f => join(dir, f)); }

let totalGz = 0;
console.log('| asset | raw (KB) | gzip (KB) |');
console.log('|---|---|---|');
for (const [name, files] of Object.entries(groups)) {
  let raw = 0, gz = 0;
  for (const f of files) { try { raw += sizeRaw(f); gz += sizeGz(f); } catch { console.error('missing', f); } }
  totalGz += gz;
  console.log(`| ${name} | ${(raw/1024).toFixed(1)} | ${(gz/1024).toFixed(1)} |`);
}
console.log(`\nTOTAL gzip ≈ ${(totalGz/1024).toFixed(1)} KB (excludes mermaid, loaded lazily)`);
```

**Step 2: Run + record verdict**

Run: `cd preview && npm run build && npm run size`
Expected: prints a table. **Decision rule (design §4):** if total gzip ≤ 600 KB → bundle offline, proceed. If > 600 KB → log which dep dominates and flag for trimming (e.g., hljs full → `common` subset). Write the numbers + verdict into `preview/docs/SIZE-REPORT.md`.

**Step 3: Commit**

```bash
git add preview/scripts/measure-size.js preview/docs/SIZE-REPORT.md
git commit -m "chore(preview): gzip size report (P0-d verdict)"
```

---

## Task 10: Playwright visual golden — the "top-tier" proof

**Files:**
- Create: `preview/playwright.config.js`
- Create: `preview/e2e/golden.spec.js`
- Create: `preview/e2e/fixtures/sample.md` (representative: headings, table, task list, code w/ highlighting, inline+block math, mermaid, image, footnote)

**Step 1: config**

```js
// preview/playwright.config.js
import { defineConfig } from '@playwright/test';
export default defineConfig({
  testDir: './e2e',
  use: { viewport: { width: 414, height: 896 } }, // phone-sized
  updateSnapshots: process.env.UPDATE_GOLDENS ? 'all' : 'missing',
});
```

**Step 2: golden spec** — serves template.html, injects the bundle + sample, screenshots per theme.

```js
// preview/e2e/golden.spec.js
import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { createServer } from 'node:http';

const sample = readFileSync('e2e/fixtures/sample.md', 'utf8');

test('light theme renders top-tier', async ({ page }) => {
  await page.goto('http://localhost:0'); // replaced by dynamic server below
  await page.evaluate((t) => window.__render__(t, 'light'), sample);
  await page.waitForFunction(() => window.__renderDone__);
  await page.waitForTimeout(500); // let mermaid settle
  await expect(page).toHaveScreenshot('light.png', { maxDiffPixelRatio: 0.01 });
});
```

> Note: serve `preview/` over a tiny static server in a `globalSetup` (Playwright) so `template.html` can fetch `dist/preview.js`, katex css, etc. — or inline them for the test. Get one theme green first; add dark as a second test. First run with `UPDATE_GOLDENS=1` to seed baselines, then run without to lock them.

**Step 3: Run**

Run: `cd preview && UPDATE_GOLDENS=1 npm run test:e2e` (seed) then `npm run test:e2e`
Expected: goldens created, then pass. **Manually eyeball `light.png`/`dark.png`** — this is the qualitative "top-tier" gate that no unit test can assert.

**Step 4: Commit**

```bash
git add preview/playwright.config.js preview/e2e/ preview/e2e/fixtures/
git commit -m "test(preview): playwright visual goldens (top-tier gate)"
```

---

## Task 11: Phase 0 spine — full green + verdict

**Step 1: Run everything**

Run: `cd preview && npm test && npm run build && npm run size && npm run test:e2e`
Expected: all unit tests pass, build succeeds, size ≤ 600 KB gzip, goldens pass.

**Step 2: Write Phase 0 spine verdict** into `preview/docs/PHASE0-VERDICT.md`:
- Rendering pipeline works standalone? (yes/no)
- Injection invariants locked? (yes)
- Top-tier visual confirmed by goldens? (manual yes/no)
- gzip within budget? (number + verdict)
- Remaining device P0 (Task 12) status: pending device access.

**Step 3: Commit + tag**

```bash
git add preview/docs/PHASE0-VERDICT.md
git commit -m "docs(phase0): preview-pipeline spine verdict"
git tag phase0-spine
```

---

## Task 12: Device verification runbook (P0 a/b/c) — out of scope to automate here

> These need a Mac (iOS) / Android device. They are **gates**: the design says if (a) or (b) fails, return to the drawing board. Track results in `preview/docs/PHASE0-DEVICE-RUNBOOK.md`.

**Files:**
- Create: `preview/docs/PHASE0-DEVICE-RUNBOOK.md`

**Checklist to write into that doc (each = a future mini-task once Flutter scaffold exists):**

- **P0(a) iOS WebView render生死:**
  - Scaffold minimal Flutter app with `flutter_inappwebview` 6.1.5, load `assets/preview/template.html` + `dist/preview.js`.
  - On an **iOS device or simulator** (needs Mac + Xcode): call `window.__render__(sample)` via `evaluateJavascript(source:)` using a **JSON-encoded** argument (design §4 — never raw interpolation).
  - Pass criteria: code highlighting, KaTeX math, and mermaid all render; `__renderDone__` callback fires; no console errors. → If any fail on iOS, this is a生死 fail.
- **P0(b) iOS bookmark 5-scenario matrix:** native plugin picks a `.md`, stores `NSURL bookmark`, then verify access survives: (1) normal relaunch (2) kill-process relaunch (3) OS upgrade (4) file moved/renamed (5) iCloud-hosted file. Record pass/fail per scenario + which of the 3 failure-branches triggers.
- **P0(c) Android SAF best-effort write:** on an Android emulator/device, write via `ContentResolver.openOutputStream(uri, "wt")`; verify (1) URI never disappears mid-write, (2) `"wt"` truncates on the target provider, (3) `.bak` + byte-count check recover after a simulated mid-write crash.
- **P0(d) large-file threshold:** open a synthetic 2 MB and 10 MB `.md`; confirm read-only-open at lower bound, reject at upper bound (design §5).

**Commit the runbook:**

```bash
git add preview/docs/PHASE0-DEVICE-RUNBOOK.md
git commit -m "docs(phase0): device verification runbook (iOS WebView / bookmark / SAF)"
```

---

## Done criteria for this plan

- `preview/` bundle: all unit tests green, build succeeds, injection invariants locked.
- gzip ≤ 600 KB (or documented trim plan).
- Playwright goldens exist and pass; **manually judged top-tier**.
- `PHASE0-VERDICT.md` records the spine verdict; device runbook committed for the next plan.

Next plan (Phase 0b): Flutter scaffold + `WebViewRenderer` integration + iOS/Android device P0 execution per the runbook.
