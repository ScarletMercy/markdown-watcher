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
  // Defensive no-op: addInitScript above re-runs on every navigation and
  // re-initializes __lastRenderDone, so this explicit re-arm is redundant.
  // Kept intentionally as a guard against any future code path that navigates
  // without re-running the init script.
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
  // IMPORTANT — what this golden does and does NOT prove:
  //
  // Only `themes/light.css` ships. There is no separate `dark.css`; "dark mode"
  // is achieved purely via the `data-theme="dark"` attribute override block
  // inside light.css. That override produces a visibly different pixel result
  // from the light golden, so this screenshot is useful as a REGRESSION ANCHOR:
  // it catches unintended pixel drift in the dark-attribute branch.
  //
  // It is NOT a proof that a distinct, fully-realized dark theme renders
  // correctly. A real dark-theme visual proof would require either a dedicated
  // dark stylesheet or explicit assertions over a dark color palette
  // (background/foreground/accent) rather than a single whole-page snapshot.
  // If dark.css is ever introduced, replace this anchor with targeted
  // dark-palette assertions.
  await render(page, 'dark');
  await expect(page).toHaveScreenshot('dark.png', { maxDiffPixelRatio: 0.01 });
});
