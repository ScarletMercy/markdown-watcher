// Tiny static file server for the Playwright visual-golden harness.
//
// The template (src/template.html) references its assets with flat URLs that
// match the Flutter WebView's served layout:
//   /katex/katex.min.css          -> node_modules/katex/dist/katex.min.css
//   /highlight/styles/github.css  -> node_modules/highlight.js/styles/github.min.css
//   /themes/light.css             -> src/themes/light.css
//   /preview.js                   -> dist/preview.js
//   /mermaid/mermaid.esm.min.mjs  -> src/mermaid/mermaid.esm.min.mjs (if present)
//
// Anything else is served from the preview/ root (e.g. /src/template.html).
// Keeps the e2e harness self-contained: no external `serve` install, no need to
// mutate the template's canonical asset URLs.
import http from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join, normalize, resolve as resolvePath } from 'node:path';

// server.mjs lives in preview/e2e/, so step up one level to reach preview/.
const E2E_DIR = dirname(fileURLToPath(import.meta.url));
const ROOT = dirname(E2E_DIR); // preview/
const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.md': 'text/markdown; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.woff2': 'font/woff2',
  '.woff': 'font/woff',
  '.ttf': 'font/ttf',
};

// Roots the server is allowed to serve from. Resolved + normalized once so
// later containment checks can be plain string-prefix comparisons.
const ALLOWED_ROOTS = [
  resolvePath(ROOT),
  resolvePath(join(ROOT, 'node_modules')),
].map(normalize);

// True if `p` is `root` itself or lives directly beneath it. Accepts both
// platform separators so the check is correct on Windows and POSIX.
function isContainedIn(p, root) {
  return p === root || p.startsWith(root + '\\') || p.startsWith(root + '/');
}

// Map a flat request path to a real file under the project tree. The path is
// NOT yet validated for containment; the caller must run validatePath() on the
// result before any filesystem access.
function resolveFile(urlPath) {
  const clean = urlPath.split('?')[0];
  // Explicit rewrites for the template's flat asset URLs.
  const rewrites = [
    ['/katex/', join(ROOT, 'node_modules/katex/dist/')],
    ['/highlight/', join(ROOT, 'node_modules/highlight.js/')],
    ['/themes/', join(ROOT, 'src/themes/')],
    ['/mermaid/', join(ROOT, 'src/mermaid/')],
    ['/preview.js', join(ROOT, 'dist/preview.js')],
  ];
  for (const [prefix, target] of rewrites) {
    if (prefix === clean) return target;
    if (clean.startsWith(prefix)) {
      return join(target, clean.slice(prefix.length));
    }
  }
  // Default: serve from preview/ root.
  return join(ROOT, clean);
}

// Validate a decoded request path before any stat/readFile. Throws a tagged
// error so the handler can map it to the right HTTP status (400 vs 403) rather
// than collapsing every failure into a generic 404.
class PathError extends Error {
  constructor(code) { super(code); this.code = code; }
}

function decodeRequestPath(rawUrlPath) {
  let decoded;
  try {
    decoded = decodeURIComponent(rawUrlPath);
  } catch (e) {
    // Malformed percent-escape (e.g. "/%zz"). Report explicitly rather than
    // falling through to a misleading 404.
    throw new PathError(400);
  }
  // Reject embedded NUL or other control chars (< 0x20) that could be used to
  // confuse downstream path handling. Defense-in-depth.
  for (let i = 0; i < decoded.length; i++) {
    const c = decoded.charCodeAt(i);
    if (c < 0x20) throw new PathError(400);
  }
  return decoded;
}

const server = http.createServer(async (req, res) => {
  try {
    // --- Path resolution + validation, BEFORE any filesystem access ---
    // 1. Decode the raw URL, surfacing malformed escapes / control chars as 400.
    const decoded = decodeRequestPath(req.url.split('?')[0]);
    // 2. Compute the candidate filesystem path from the decoded URL.
    const candidate = resolveFile(decoded);
    // 3. Normalize and check containment in an allowed root. Reject with 403
    //    BEFORE statting so a traversal probe never touches the disk.
    const normalized = normalize(candidate);
    if (!ALLOWED_ROOTS.some((r) => isContainedIn(normalized, r))) {
      res.writeHead(403).end('forbidden');
      return;
    }
    // --- Only now is it safe to touch the filesystem ---
    let filePath = normalized;
    // Directory index / trailing slash -> try index.html.
    const s = await stat(filePath).catch(() => null);
    if (s && s.isDirectory()) {
      filePath = join(filePath, 'index.html');
    }
    const data = await readFile(filePath);
    const ext = filePath.slice(filePath.lastIndexOf('.')).toLowerCase();
    res.writeHead(200, { 'Content-Type': MIME[ext] || 'application/octet-stream' });
    res.end(data);
  } catch (e) {
    if (e instanceof PathError) {
      res.writeHead(e.code).end(e.code === 400 ? 'bad request' : 'forbidden');
      return;
    }
    res.writeHead(404).end('not found: ' + req.url);
  }
});

const PORT = process.env.PORT || 5179;
server.listen(PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`preview e2e server on http://localhost:${PORT}`);
});
