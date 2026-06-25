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
