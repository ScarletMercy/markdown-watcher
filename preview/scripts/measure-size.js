// preview/scripts/measure-size.js
// Measures raw + gzip sizes of preview bundle assets and prints a markdown table.
// Used by `npm run size`. Part of Unit 5 (Plan Task 9) — P0(d) gzip budget verdict.
import { gzipSync } from 'node:zlib';
import { statSync, readFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// Anchor paths to the script's own location so it works regardless of cwd.
const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..'); // preview/ root

function sizeGz(p) { return gzipSync(readFileSync(p)).length; }
function sizeRaw(p) { return statSync(p).size; }

// Paths are relative to the preview/ directory.
const groups = {
  'dist/preview.js (markdown-it+katex+hljs bundle)': ['dist/preview.js'],
  'katex min css': ['node_modules/katex/dist/katex.min.css'],
  'highlight github theme css': ['node_modules/highlight.js/styles/github.min.css'],
  'themes light.css': ['src/themes/light.css'],
};

console.log('| asset | raw (KB) | gzip (KB) |');
console.log('|---|---|---');
let totalRaw = 0;
let totalGz = 0;
let missing = false;
for (const [name, files] of Object.entries(groups)) {
  let raw = 0, gz = 0;
  for (const rel of files) {
    const f = join(ROOT, rel);
    if (!existsSync(f)) {
      console.error(`error: ${rel} not found — run \`npm run build\` first`);
      missing = true;
      continue;
    }
    raw += sizeRaw(f);
    gz += sizeGz(f);
  }
  totalRaw += raw;
  totalGz += gz;
  console.log(`| ${name} | ${(raw / 1024).toFixed(1)} | ${(gz / 1024).toFixed(1)} |`);
}
console.log(`\nTOTAL raw ≈ ${(totalRaw / 1024).toFixed(1)} KB | TOTAL gzip ≈ ${(totalGz / 1024).toFixed(1)} KB (excludes mermaid, loaded lazily)`);

if (missing) process.exitCode = 1;
