import { test } from 'node:test';
import assert from 'node:assert/strict';
import { renderMarkdown } from '../src/render.js';

test('heading + paragraph + bold', () => {
  const html = renderMarkdown('# Title\n\nSome **bold** text.\n');
  assert.match(html, /<h1[^>]*>.*Title.*<\/h1>/s);
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
