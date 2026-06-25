// Structural gate (no browser required) for the same representative sample the
// Playwright visual-golden test renders. This is the always-on fallback that
// proves the full rendering surface is wired even when Chromium is unavailable.
//
// It asserts the *shape* of renderMarkdown(sample): every top-level feature
// (headings, table, task list, highlighted code, KaTeX, mermaid passthrough,
// footnotes) must produce its expected HTML scaffold. Pixel-exact "top-tier"
// verdict still requires the golden in e2e/; this guarantees nothing regressed
// structurally.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { renderMarkdown } from '../src/render.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const sample = readFileSync(join(__dirname, '..', 'e2e', 'fixtures', 'sample.md'), 'utf8');
const html = renderMarkdown(sample);

test('headings h1/h2/h3 present', () => {
  assert.match(html, /<h1/);
  assert.match(html, /<h2/);
  assert.match(html, /<h3/);
});

test('emphasis: bold/italic/strikethrough/code', () => {
  assert.match(html, /<strong>/);
  assert.match(html, /<em>/);
  // markdown-it renders GFM strikethrough as <s> (markdown-it 14 default).
  assert.match(html, /<s>strikethrough<\/s>/);
  assert.match(html, /<code>inline code<\/code>/);
});

test('unordered + ordered lists', () => {
  assert.match(html, /<ul/);
  assert.match(html, /<ol/);
});

test('task list item tagged with data-task', () => {
  assert.match(html, /<li[^>]*data-task/);
  // checked + unchecked variants both present in the sample
  assert.match(html, /<li[^>]*data-checked/);
  assert.match(html, /<li[^>]*data-unchecked/);
});

test('blockquote rendered', () => {
  assert.match(html, /<blockquote/);
});

test('fenced code block highlighted with hljs', () => {
  assert.match(html, /<pre class="hljs">/);
});

test('table 2x3 (header + separator + rows)', () => {
  // The source_lines ruler adds data-source-line, so match on the tag start.
  assert.match(html, /<table\b/);
  assert.match(html, /<thead\b/);
  assert.match(html, /<tbody\b/);
});

test('inline + block math rendered via KaTeX', () => {
  assert.match(html, /katex/);
  // Block math should yield a display-style KaTeX block.
  assert.match(html, /class="katex-display"/);
});

test('mermaid fence passes through as a .mermaid div', () => {
  assert.match(html, /<div class="mermaid"/);
  // Source content is escaped inside, not executed as a real fence here.
  assert.match(html, /graph TD/);
});

test('footnote section produced', () => {
  assert.match(html, /footnotes/);
});
