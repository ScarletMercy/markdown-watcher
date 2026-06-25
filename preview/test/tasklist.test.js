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
