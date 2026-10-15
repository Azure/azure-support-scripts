/**
 * @module tests/accessibility
 * @description Playwright accessibility tests using axe-core.
 *
 * Validates WCAG 2.1 AA compliance on both the empty state and
 * after a file upload has been processed.  Uses `@axe-core/playwright`
 * for automated checks.
 */
import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { uploadAndWaitForAnalysis, navigateToApp, fixturePath } from './test-helpers.js';

test.describe('Accessibility (WCAG 2.1 AA)', () => {

  test.beforeEach(async ({ page }, testInfo) => {
    await navigateToApp(page, testInfo);
    await expect(page.locator('h1')).toContainText('RCA Tool');
  });

  test('empty state has no WCAG 2.1 AA violations', async ({ page }) => {
    const results = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'])
      .analyze();

    expect(results.violations).toEqual([]);
  });

  test('post-analysis state has no WCAG 2.1 AA violations', async ({ page }) => {
    await uploadAndWaitForAnalysis(page, 'scc_test-azure-vm.tar.xz');

    const results = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'])
      .analyze();

    // Log detailed violation info for debugging
    if (results.violations.length > 0) {
      for (const v of results.violations) {
        console.log(`[a11y] ${v.id} (${v.impact}): ${v.help}`);
        for (const node of v.nodes) {
          console.log(`  → ${node.target.join(' ')}`);
        }
      }
    }

    expect(results.violations).toEqual([]);
  });

  test('output region has correct ARIA attributes', async ({ page }) => {
    const output = page.locator('#output');
    await expect(output).toHaveAttribute('role', 'region');
    await expect(output).toHaveAttribute('aria-live', 'polite');
    await expect(output).toHaveAttribute('aria-label', 'Analysis results');
  });

  test('all external links have rel=noopener', async ({ page }) => {
    await uploadAndWaitForAnalysis(page, 'scc_test-azure-vm.tar.xz');

    const unsafeLinks = await page.locator('a[target="_blank"]:not([rel*="noopener"])').count();
    expect(unsafeLinks).toBe(0);
  });

  test('all table headers have scope attribute', async ({ page }) => {
    await uploadAndWaitForAnalysis(page, 'scc_test-azure-vm.tar.xz');

    const thWithoutScope = await page.locator('th:not([scope])').count();
    expect(thWithoutScope).toBe(0);
  });
});
