// preview/scripts/measure-size.js
// Measures raw + gzip sizes of preview bundle assets and prints a markdown table.
// Used by `npm run size`. Part of Unit 5 (Plan Task 9) — P0(d) gzip budget verdict.
import { gzipSync } from 'node:zlib';
import { statSync, readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';

function sizeGz(p) { return gzipSync(readFileSync(p)).length; }
function sizeRaw(p) { return statSync(p).size; }

// Paths are relative to the preview/ directory (cwd when invoked via npm run).
const groups = {
  'dist/preview.js (markdown-it+katex+hljs bundle)': ['dist/preview.js'],
  'katex min css': ['node_modules/katex/dist/katex.min.css'],
  'highlight github theme css': ['node_modules/highlight.js/styles/github.min.css'],
  'themes light.css': ['src/themes/light.css'],
};

console.log('| asset | raw (KB) | gzip (KB) |');
console.log('|---|---|---|');
let totalGz = 0;
for (const [name, files] of Object.entries(groups)) {
  let raw = 0, gz = 0;
  for (const f of files) {
    if (!existsSync(f)) { console.error('missing:', f); continue; }
    raw += sizeRaw(f); gz += sizeGz(f);
  }
  totalGz += gz;
  console.log(`| ${name} | ${(raw / 1024).toFixed(1)} | ${(gz / 1024).toFixed(1)} |`);
}
console.log(`\nTOTAL gzip ≈ ${(totalGz / 1024).toFixed(1)} KB (excludes mermaid, loaded lazily)`);
