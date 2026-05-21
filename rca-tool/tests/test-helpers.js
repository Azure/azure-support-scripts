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
  
  // Wait for the final results view rather than the transient progress view.
  // On slower CI runners, `#output.innerHTML.length > 100` can become true
  // while the file is still being analysed, which makes the tests flaky.
  await page.waitForFunction((expectedFilename) => {
    const output = document.getElementById('output');
    if (!output) return false;

    const header = output.querySelector('.analysis-header h2');
    const button = output.querySelector('.analysis-header button');
    const progress = output.querySelector('.progress-container');
    const results = output.querySelector('.analysis-results');

    const headerText = header?.textContent || '';
    const buttonText = button?.textContent || '';

    return headerText.includes(expectedFilename)
      && buttonText.includes('Analyse another file')
      && !progress
      && !!results;
  }, filename, { timeout: 60000 });

  // Give the DOM a brief moment to settle before snapshotting the HTML.
  await page.waitForTimeout(100);

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
 * Navigate to the RCA Tool app root, always preferring the Leptos UI for
 * local runs and using the deployed site root in hosted environments.
 *
 * @async
 * @param {Object} page - Playwright page object.
 * @param {Object} testInfo - Playwright test info.
 */
export async function navigateToApp(page, testInfo) {
  const projectName = testInfo.project.name || '';
  const isDeployed = projectName === 'deployed' || projectName.includes('deployed');
  const cacheBuster = isDeployed && process.env.CACHE_BUSTER
    ? `?cb=${encodeURIComponent(process.env.CACHE_BUSTER)}`
    : '';

  if (isDeployed) {
    await page.goto(`./${cacheBuster}`);
    return;
  }

  // Local runs may serve the app at '/' (current) or '/web-leptos/dist/' (legacy).
  // Try root first and fall back for compatibility.
  const localCandidates = [
    `/${cacheBuster}`,
    `/web-leptos/dist/${cacheBuster}`
  ];

  let lastError;
  for (const candidate of localCandidates) {
    try {
      await page.goto(candidate);
      return;
    } catch (error) {
      lastError = error;
    }
  }

  throw lastError;
}
