# Preview Bundle — gzip Size Report (P0-d)

> Unit 5 / Plan Task 9. Measured on `phase-0` with `highlight.js@11.11.1`, `katex@0.17.0`,
> `markdown-it@14.2.0`, esbuild minified IIFE build.

## Budget (design §4)

- Total gzip assets **≤ 600 KB**.
- **Mermaid is excluded** — it is lazy-loaded as a separate chunk and not measured here.

## Measured sizes (`npm run build && npm run size`)

| asset | raw (KB) | gzip (KB) |
|---|---|---|
| dist/preview.js (markdown-it+katex+hljs bundle) | 1742.7 | 515.8 |
| katex min css | 23.3 | 3.5 |
| highlight github theme css | 1.3 | 0.6 |
| themes light.css | 0.9 | 0.5 |

**TOTAL gzip ≈ 520.4 KB** (excludes mermaid, loaded lazily)

## Verdict

**WITHIN the 600 KB budget** (520.4 KB gzip, ~80 KB of headroom).

## Dominant contributor — highlight.js full language set

The `dist/preview.js` bundle (515.8 KB gzip) is dominated by highlight.js, which
ships the **full** language set (~190 languages). A direct build probe (esbuild,
same `minify`/`target` as the production config) comparing entry points:

| hljs entry | raw (KB) | gzip (KB) |
|---|---|---|
| `highlight.js/lib/index.js` (full, ~190 langs) | 1054.7 | 306.8 |
| `highlight.js/lib/common.js` (~35 common langs) | 157.4 | 52.2 |
| **gzip saving if switching to common** | — | **254.6** |

So ~307 KB gzip (≈59%) of the JS bundle is highlight.js full; switching to the
`common` subset would remove ~255 KB gzip and bring the bundle down to roughly
**~265 KB gzip total** (520.4 − 254.6).

## Recommendation

The bundle ships **within budget today**, so for the MVP we may ship as-is.
However, because highlight.js (full) consumes ~59% of the JS gzip and leaves only
~80 KB of headroom against the 600 KB budget, the recommended forward path is:

> **Adopt `highlight.js/lib/common` as the default language set and register extra
> languages on demand** (e.g. `hljs.registerLanguage('rust', rust)` for the few
> beyond common that users actually need). This drops total gzip from ~520 KB to
> ~265 KB, frees ~335 KB of budget headroom for future features, and removes the
> risk of any added dependency pushing the bundle over budget.

`katex` (3.5 KB gzip) and the theme CSS (0.6 + 0.5 KB gzip) are negligible;
no action needed there. Mermaid remains a lazy-loaded separate chunk and is
not counted.

## Next action item

- [ ] Open a follow-up task: switch `src/render.js` (or the hljs import site) from
  `highlight.js` to `highlight.js/lib/common`, re-run `npm run size` to confirm
  the ~255 KB gzip drop, and add a unit test asserting the registered-language
  set so accidental re-import of the full bundle is caught in CI.

## Reproducing

```bash
cd preview
npm run build      # esbuild → dist/preview.js
npm run size       # prints the table above
```
