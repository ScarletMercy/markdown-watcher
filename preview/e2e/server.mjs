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

// Map a flat request path to a real file under the project tree.
function resolveFile(urlPath) {
  const clean = decodeURIComponent(urlPath.split('?')[0]);
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

const server = http.createServer(async (req, res) => {
  try {
    let filePath = resolveFile(req.url);
    // Directory index / trailing slash -> try index.html.
    const s = await stat(filePath).catch(() => null);
    if (s && s.isDirectory()) {
      filePath = join(filePath, 'index.html');
    }
    // Guard against path traversal escaping ROOT or its known rewrite roots.
    const normalized = normalize(filePath);
    const allowedRoots = [
      resolvePath(ROOT),
      resolvePath(join(ROOT, 'node_modules')),
    ].map(normalize);
    if (!allowedRoots.some((r) => normalized === r || normalized.startsWith(r + '\\') || normalized.startsWith(r + '/'))) {
      res.writeHead(403).end('forbidden');
      return;
    }
    const data = await readFile(filePath);
    const ext = filePath.slice(filePath.lastIndexOf('.')).toLowerCase();
    res.writeHead(200, { 'Content-Type': MIME[ext] || 'application/octet-stream' });
    res.end(data);
  } catch (e) {
    res.writeHead(404).end('not found: ' + req.url);
  }
});

const PORT = process.env.PORT || 5179;
server.listen(PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`preview e2e server on http://localhost:${PORT}`);
});
