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
// Mirrors markdown-it's `fence` rule (node_modules/markdown-it/lib/rules_block/
// fence.mjs) for opening detection, indentation guard, and closing-scan logic,
// but restricted to the `mermaid` info string. Supports both ``` and ~~~ fences
// symmetrically (CommonMark). Non-mermaid fences fall through to the default
// `fence` rule (registered after this one) for hljs highlighting.
md.block.ruler.before('fence', 'mermaid_fence', (state, startLine, endLine, silent) => {
  // Indentation guard: lines indented >= 4 spaces are indented code blocks.
  if (state.sCount[startLine] - state.blkIndent >= 4) return false;

  const start = state.bMarks[startLine] + state.tShift[startLine];
  const lineMax = state.eMarks[startLine];
  const markerCharCode = state.src.charCodeAt(start);
  // Opening marker must be a run of backticks or tildes.
  if (markerCharCode !== 0x60 /* ` */ && markerCharCode !== 0x7E /* ~ */) return false;

  // Scan the marker run length.
  let pos = start;
  while (pos < lineMax && state.src.charCodeAt(pos) === markerCharCode) pos++;
  const markerLen = pos - start;
  if (markerLen < 3) return false;
  const markup = state.src.slice(start, pos);

  // Info string = rest of the opening line. For backtick fences, markdown-it
  // rejects a backtick in the info string (unterminated inline code); mirror that.
  const params = state.src.slice(pos, lineMax);
  if (markerCharCode === 0x60 && params.indexOf('`') >= 0) return false;

  if (params.trim() !== 'mermaid') return false;

  if (silent) return true;

  // Scan for the closing fence, mirroring markdown-it/fence.mjs: a closing
  // fence is a run of the same marker (length >= opening) followed by
  // whitespace-only to end-of-line. This avoids splitting on a triple-backtick
  // line that is mermaid *content* (e.g. code in node text).
  let nextLine = startLine;
  let haveEnd = false;
  while (true) {
    nextLine++;
    if (nextLine >= endLine) break; // EOF / end of parent: autoclose
    let ls = state.bMarks[nextLine] + state.tShift[nextLine];
    const lm = state.eMarks[nextLine];
    // Closing fence cannot be indented >= 4 spaces.
    if (state.sCount[nextLine] - state.blkIndent >= 4) continue;
    if (state.src.charCodeAt(ls) !== markerCharCode) continue;
    // Run of the same marker at least as long as the opening run.
    let p = ls;
    while (p < lm && state.src.charCodeAt(p) === markerCharCode) p++;
    if (p - ls < markerLen) continue;
    // Rest of line must be whitespace-only to count as a closing fence.
    while (p < lm && (state.src.charCodeAt(p) === 0x20 || state.src.charCodeAt(p) === 0x09)) p++;
    if (p === lm) { haveEnd = true; break; }
  }

  const content = state.getLines(startLine + 1, nextLine, state.tShift[startLine], false).trim();
  const token = state.push('mermaid', 'div', 0);
  token.content = content;
  token.map = [startLine, nextLine];
  token.markup = markup;
  token.info = 'mermaid';
  // Only advance past the closing marker line if one was actually found;
  // otherwise an unclosed fence at EOF would overshoot state.line by 1.
  state.line = nextLine + (haveEnd ? 1 : 0);
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
