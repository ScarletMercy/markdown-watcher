// Playwright visual-golden config for the markdown-watcher preview.
//
// Phone-sized viewport (iPhone-ish 414x896) because the template renders for a
// Flutter WebView and the goldens should be representative of that target.
// `UPDATE_GOLDENS=1` rebuilds snapshots; otherwise snapshots are only written
// when missing (fail-fast on drift against committed goldens).
import { defineConfig } from '@playwright/test';
import { fileURLToPath } from 'node:url';
const __dirname = fileURLToPath(new URL('.', import.meta.url));

export default defineConfig({
  testDir: './e2e',
  use: { viewport: { width: 414, height: 896 } },
  updateSnapshots: process.env.UPDATE_GOLDENS ? 'all' : 'missing',
  // Static server that rewrites the template's flat asset URLs to the real
  // locations under node_modules/ and the project tree. See e2e/server.mjs.
  webServer: {
    command: 'node e2e/server.mjs',
    port: 5179,
    reuseExistingServer: true,
    cwd: __dirname,
    timeout: 30000,
  },
});
