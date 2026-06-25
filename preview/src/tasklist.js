// Hand-written GitHub-style task-list rule.
//
// We deliberately avoid the archived `markdown-it-task-lists` plugin and
// implement the minimal behaviour we need: detect GFM task markers
// (`- [ ]` / `- [x]`) at the start of a list item, strip the marker from the
// rendered text, tag the <li> with data-* attrs, and prepend a disabled
// <input type=checkbox>.
//
// Limitation: only the first line of a list item is treated as the task label
// (matching GitHub). The marker must be the very first inline content.

const MARKER = /^\[([ xX])\][ \t]+/;

export default function taskList(md) {
  // Core rule: runs after inline parsing, so the item's text is already a
  // sequence of inline tokens. We rewrite the first text token and re-derive
  // children when the marker is present.
  md.core.ruler.after('inline', 'task_lists', (state) => {
    const t = state.tokens;
    for (let i = 0; i < t.length; i++) {
      if (t[i].type !== 'inline') continue;
      // The inline must be the item's content: it follows list_item_open
      // either directly (tight list) or via paragraph_open (loose / single).
      const prev1 = t[i - 1];
      const prev2 = t[i - 2];
      const isItemContent =
        (prev2 && prev2.type === 'list_item_open') || // paragraph_open in between
        (prev1 && prev1.type === 'list_item_open');   // tight list
      if (!isItemContent) continue;

      const firstText = t[i].children && t[i].children[0];
      if (!firstText || firstText.type !== 'text') continue;
      const m = MARKER.exec(firstText.content);
      if (!m) continue;

      const checked = m[1].toLowerCase() === 'x';

      // Rewrite the first text token's content, then re-tokenize the entire
      // inline run so downstream rules (smartquotes, etc.) see the cleaned
      // text rather than stale children.
      const remaining = firstText.content.slice(m[0].length);
      // Re-tokenize the stripped text IN PLACE: markdown-it's inline.parse
      // populates the destination array it is given (it does not return one),
      // and downstream core rules (text_join, smartquotes, ...) hold the
      // existing `children` reference, so we must mutate it rather than
      // replace it. Clear then refill.
      t[i].children.length = 0;
      md.inline.parse(remaining, state.md, state.env, t[i].children);
      t[i].content = remaining;

      // Tag the list_item_open token (grandparent of inline for loose lists,
      // parent for tight). attrSet is idempotent.
      const itemOpen = (prev2 && prev2.type === 'list_item_open') ? prev2 : prev1;
      itemOpen.attrSet('data-task', '');
      if (checked) itemOpen.attrSet('data-checked', '');
      else itemOpen.attrSet('data-unchecked', '');
    }
  });

  // Renderer override: emit a disabled checkbox right after the <li> open tag
  // for items we tagged above.
  const defaultListItemOpen = md.renderer.rules.list_item_open
    || ((tokens, idx, opts, env, self) => self.renderToken(tokens, idx, opts));
  md.renderer.rules.list_item_open = (tokens, idx, opts, env, self) => {
    const out = defaultListItemOpen(tokens, idx, opts, env, self);
    if (tokens[idx].attrGet('data-task') !== null) {
      const checked = tokens[idx].attrGet('data-checked') !== null;
      return out + `<input type="checkbox" disabled${checked ? ' checked' : ''}> `;
    }
    return out;
  };
}
