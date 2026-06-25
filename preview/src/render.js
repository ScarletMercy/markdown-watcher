import MarkdownIt from 'markdown-it';
import footnote from 'markdown-it-footnote';
import anchor from 'markdown-it-anchor';
import texmath from 'markdown-it-texmath';
import katex from 'katex';
import hljs from 'highlight.js';
import taskList from './tasklist.js';

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
  .use(anchor, { permalink: anchor.permalink.headerLink() })
  .use(taskList);

// Mermaid fences pass through as `<div class="mermaid">…</div>` (escaped content
// + data-source-line). Actual SVG rendering happens WebView-side (browser DOM),
// not here in Node — see the HTML template (later unit). Registered BEFORE the
// default `fence` rule so non-mermaid fences (```js, …) still fall through to
// the default fence rule and get hljs highlighting.
md.block.ruler.before('fence', 'mermaid_fence', (state, startLine, endLine, silent) => {
  const start = state.bMarks[startLine] + state.tShift[startLine];
  const marker = state.src.slice(start, start + 3);
  if (marker !== '```') return false;
  // info string after the fence
  let pos = start + 3;
  const langStart = pos;
  while (pos < state.eMarks[startLine] && state.src.charCodeAt(pos) !== 0x20 /*space*/) pos++;
  const lang = state.src.slice(langStart, pos).trim();
  if (lang !== 'mermaid') return false;
  if (silent) return true;
  // collect until a closing fence of at least 3 backticks
  let nextLine = startLine + 1;
  while (nextLine < endLine) {
    const ls = state.bMarks[nextLine] + state.tShift[nextLine];
    if (state.src.slice(ls, ls + 3) === '```') break;
    nextLine++;
  }
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

// Tag every opening block token with the source line it came from, so the
// Flutter WebView can map DOM nodes back to markdown offsets for scroll-sync.
// Chained before `anchor` for determinism; both rules `attrSet` on the same
// `heading_open` token and neither splices block tokens, so order does not
// currently affect output.
//
// Known limitation: only block-level tokens have a `map`; inline tokens and
// the implicit <p> tokens of tight lists have no map and are skipped.
// Block-level anchors are sufficient for scroll-sync purposes.
//
// Known limitation: fenced code blocks currently get NO `data-source-line`.
// The custom `highlight` callback above returns raw HTML (a fully-rendered
// `<pre><code>...</code></pre>` string) instead of producing a `fence_open`
// token with a `map` to tag, so the source-line ruler has nothing to annotate.
// Fixing this requires a fence-renderer-level change and is tracked for a
// later unit; it affects scroll-sync coverage of code blocks.
md.core.ruler.before('anchor', 'source_lines', (state) => {
  for (const tok of state.tokens) {
    if (tok.map && tok.nesting === 1) {
      tok.attrSet('data-source-line', String(tok.map[0]));
    }
  }
});

export function renderMarkdown(text) {
  return md.render(text);
}

export { md };
