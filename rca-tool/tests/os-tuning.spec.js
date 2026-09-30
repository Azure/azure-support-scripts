/**
 * @module tests/os-tuning
 * @description Playwright tests for the OS Tuning and Security section.
 *
 * Covers the four SAP-on-Azure QualityCheck ports surfaced by the Leptos UI:
 * tuned profile, SELinux mode, swap space, and the fstrim timer.  The
 * `scc_test-os-tuning.tar.xz` fixture is crafted to trigger one warning per
 * detector (SELinux enforcing, no swap configured, fstrim timer enabled) plus
 * a tuned recommendation.
 */
import { test, expect } from './coverage-fixture.js';
import { uploadAndWaitForAnalysis, navigateToApp } from './test-helpers.js';

test.describe('OS Tuning and Security', () => {

  test.beforeEach(async ({ page }, testInfo) => {
    await navigateToApp(page, testInfo);
    await expect(page.locator('h1')).toContainText('RCA Tool');
  });

  test('renders tuned, SELinux, swap, and fstrim findings', async ({ page }) => {
    const html = await uploadAndWaitForAnalysis(page, 'scc_test-os-tuning.tar.xz');

    // Section is present.
    expect(html).toContain('OS Tuning and Security');

    // Tuned profile.
    expect(html).toContain('Tuned Profile:');
    expect(html).toContain('Active profile');
    expect(html).toContain('sap-hana');

    // SELinux enforcing warning.
    expect(html).toContain('SELinux:');
    expect(html).toContain('Current mode');
    expect(html).toContain('enforcing');
    expect(html).toContain('SELinux is in enforcing mode.');

    // Swap space warning (no swap configured).
    expect(html).toContain('Swap Space:');
    expect(html).toContain('Swap total');
    expect(html).toContain('No swap space is configured');

    // fstrim timer warning.
    expect(html).toContain('fstrim Timer:');
    expect(html).toContain('Timer state');
    expect(html).toContain('enabled');
  });
});
