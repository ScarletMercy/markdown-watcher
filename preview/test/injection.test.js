import { test } from 'node:test';
import assert from 'node:assert/strict';
import { renderMarkdown } from '../src/render.js';

test('raw HTML is escaped, not executed (html:false)', () => {
  const html = renderMarkdown('<script>alert(1)</script>\n');
  assert.doesNotMatch(html, /<script>alert/);
  assert.match(html, /&lt;script&gt;/);
});

test('code span escapes closing script tag', () => {
  const html = renderMarkdown('`</script>`\n');
  assert.match(html, /&lt;\/script&gt;/);
  assert.doesNotMatch(html, /<\/script>/);
});

test('template-literal / backtick payloads are inert', () => {
  const html = renderMarkdown('`${alert(1)}`\n');
  assert.match(html, /alert\(1\)/);
  assert.doesNotMatch(html, /<script/);
});

test('U+2028 line separator does not break rendering', () => {
  const html = renderMarkdown('a b\n');
  assert.match(html, /a/);
  assert.match(html, /b/);
});
