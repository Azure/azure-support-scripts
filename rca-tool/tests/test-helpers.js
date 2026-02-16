/**
 * @module tests/test-helpers
 * @description Shared Playwright test utilities for the RCA Tool test suite.
 *
 * Provides reusable helper functions that eliminate boilerplate across all
 * spec files.  Every helper is designed for both the `local` project
 * (http-server on port 8080) and the `deployed` project (GitHub Pages).
 *
 * ### Exported helpers
 *
 * | Function | Purpose |
 * |----------|--------|
 * | {@link uploadAndWaitForAnalysis} | Upload a fixture file and return the rendered `#output` HTML |
 * | {@link getResultText} | Return the plain-text content of `#output` |
 * | {@link isSapDetectedFromResult} | Check whether SAP indicators were rendered |
 * | {@link fixturePath} | Resolve an absolute path to a file inside `tests/fixtures/` |
 * | {@link navigateToApp} | Navigate to the app root, respecting the active Playwright project |
 */
import path from 'path';
import { fileURLToPath } from 'url';

const __fixturesDir = path.join(path.dirname(fileURLToPath(import.meta.url)), 'fixtures');

/**
 * Upload a fixture archive and wait for the analysis to render.
 *
 * @async
 * @param {Object} page - Playwright page object.
 * @param {string} filename - Name of the fixture file inside `tests/fixtures/`.
 * @returns {Promise<string>} The inner HTML of the `#output` element.
 */
export async function uploadAndWaitForAnalysis(page, filename) {
  const filePath = path.join(__fixturesDir, filename);
  
  // Upload file
  const fileInput = await page.locator('input[type="file"]');
  await fileInput.setInputFiles(filePath);
  
  // Wait for analysis to complete (look for results content in #output)
  await page.waitForFunction(() => {
    const output = document.getElementById('output');
    return output && output.innerHTML.length > 100;
  }, { timeout: 60000 });
  
  // Wait a bit more to ensure all content is rendered
  await page.waitForTimeout(2000);
  
  // Get the analysis result HTML
  const resultHTML = await page.locator('#output').innerHTML();
  
  return resultHTML;
}

/**
 * Extract the plain-text content of the result panel.
 *
 * @async
 * @param {Object} page - Playwright page object.
 * @returns {Promise<string>} Plain text of `#output`.
 */
export async function getResultText(page) {
  return await page.locator('#output').textContent();
}

/**
 * Check whether the rendered HTML contains SAP detection indicators.
 *
 * @param {string} resultHtml - The inner HTML returned by {@link uploadAndWaitForAnalysis}.
 * @returns {boolean} `true` when SAP Application Detection with indicators is present.
 */
export function isSapDetectedFromResult(resultHtml) {
  if (!resultHtml) return false;
  return resultHtml.includes('SAP Application Detection') && resultHtml.includes('(indicators found)');
}

/**
 * Resolve the absolute path to a fixture file.
 *
 * @param {string} filename - Fixture file name (e.g. `'scc_test-azure-vm.tar.xz'`).
 * @returns {string} Absolute file-system path.
 */
export function fixturePath(filename) {
  return path.join(__fixturesDir, filename);
}

/**
 * Navigate to the RCA Tool app root, choosing the correct path for the
 * active Playwright project (`local` → `/web/dist/`, `deployed` → `./`).
 *
 * @async
 * @param {Object} page - Playwright page object.
 * @param {Object} testInfo - Playwright test info.
 */
export async function navigateToApp(page, testInfo) {
  const navPath = testInfo.project.name === 'deployed' ? './' : '/web/dist/';
  await page.goto(navPath);
}
