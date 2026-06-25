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

test('task with bare URL preserves the link', () => {
  const html = renderMarkdown('- [ ] see https://example.com now\n');
  assert.match(html, /<a href="https:\/\/example\.com">/);
  assert.match(html, /now<\/li>/);
});

test('task with HTML entity is preserved', () => {
  const html = renderMarkdown('- [ ] a &amp; b\n');
  assert.match(html, /a.*b<\/li>/s);
  assert.match(html, /&amp;/);
});
