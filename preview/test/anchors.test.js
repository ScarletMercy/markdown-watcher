import { test } from 'node:test';
import assert from 'node:assert/strict';
import { renderMarkdown } from '../src/render.js';

test('block open tags carry data-source-line', () => {
  const html = renderMarkdown('# H\n\npara\n\n- a\n- b\n');
  assert.match(html, /<h1[^>]*data-source-line="0"/);
  assert.match(html, /<p[^>]*data-source-line="2"/);
  assert.match(html, /<ul[^>]*data-source-line="4"/);
});

test('tokens without map are skipped (no crash)', () => {
  assert.doesNotThrow(() => renderMarkdown('---\n'));
});
