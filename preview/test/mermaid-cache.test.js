import { test } from 'node:test';
import assert from 'node:assert/strict';
import { renderMarkdown } from '../src/render.js';
import { shouldRender } from '../src/mermaid-cache.js';

test('mermaid fence becomes a mermaid div', () => {
  const html = renderMarkdown('```mermaid\ngraph TD; A-->B\n```\n');
  // content is HTML-escaped (A--> becomes A--&gt;B) for safe passthrough
  assert.match(html, /<div class="mermaid"[^>]*>graph TD; A--&gt;B<\/div>/);
});

test('cache skips unchanged source, renders changed', () => {
  const cache = new Map();
  assert.equal(shouldRender('id1', 'same', cache), true);   // first time
  assert.equal(shouldRender('id1', 'same', cache), false);  // unchanged
  assert.equal(shouldRender('id1', 'changed', cache), true);// changed
});
