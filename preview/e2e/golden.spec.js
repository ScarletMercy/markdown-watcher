// Visual-golden test: render the representative sample in light & dark themes
// and assert the pixels are stable. This is the qualitative "top-tier" gate.
//
// The template calls window.__renderDone__(outline) once rendering (including
// any mermaid run) settles. We install a capture shim BEFORE invoking
// window.__render__ so we can await a deterministic signal rather than guessing
// with a fixed timeout.
import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join as joinPath } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const sample = readFileSync(joinPath(__dirname, 'fixtures/sample.md'), 'utf8');

const BASE = 'http://localhost:5179/src/template.html';

async function render(page, theme) {
  // Capture the render-done callback into a flag the spec can poll.
  await page.addInitScript(() => {
    window.__renderDone__ = () => { window.__lastRenderDone = true; };
    window.__lastRenderDone = false;
  });
  await page.goto(BASE);
  // Re-arm in case navigation reset the flag.
  await page.evaluate(() => { window.__lastRenderDone = false; });
  await page.evaluate(
    ([t, th]) => window.__render__(t, th),
    [sample, theme],
  );
  await page.waitForFunction(() => window.__lastRenderDone === true, { timeout: 15000 });
  // Extra settle for late paint / mermaid async SVG postprocessing.
  await page.waitForTimeout(800);
}

test('light theme renders top-tier', async ({ page }) => {
  await render(page, 'light');
  await expect(page).toHaveScreenshot('light.png', { maxDiffPixelRatio: 0.01 });
});

test('dark theme renders top-tier', async ({ page }) => {
  // Only light.css ships; dark still flips data-theme=dark on <html>.
  await render(page, 'dark');
  await expect(page).toHaveScreenshot('dark.png', { maxDiffPixelRatio: 0.01 });
});
