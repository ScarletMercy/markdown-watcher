function hash(s) {
  let h = 5381;
  for (let i = 0; i < s.length; i++) h = ((h << 5) + h + s.charCodeAt(i)) | 0;
  return String(h);
}

/**
 * Decide whether a mermaid block should be (re)rendered.
 *
 * Side effects: UPDATES `cache` — records the latest digest for `id` so a
 * subsequent call with unchanged `source` returns false. Callers do not need
 * to write the cache themselves.
 *
 * Contract: `id` must be STABLE across re-renders for the same logical block
 * (i.e. derived from position/order in the document, not a fresh per-render
 * random/sequence id). If `id` changes between renders, every block looks
 * "new" and the cache never saves work. This matters when Unit 4's template
 * wires shouldRender in: assign per-block ids deterministically.
 *
 * @param {string} id      Stable per-block identifier.
 * @param {string} source  Raw mermaid source for the block.
 * @param {Map} cache      Shared cache map (mutated as a side effect).
 * @returns {boolean} true if the block is new or its source changed since the
 *                    last call for this `id`; false if it is unchanged.
 */
export function shouldRender(id, source, cache) {
  const digest = hash(source);
  if (cache.get(id) === digest) return false;
  cache.set(id, digest);
  return true;
}
