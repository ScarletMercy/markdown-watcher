function hash(s) {
  let h = 5381;
  for (let i = 0; i < s.length; i++) h = ((h << 5) + h + s.charCodeAt(i)) | 0;
  return String(h);
}

// Returns true if the block should be (re)rendered.
export function shouldRender(id, source, cache) {
  const digest = hash(source);
  if (cache.get(id) === digest) return false;
  cache.set(id, digest);
  return true;
}
