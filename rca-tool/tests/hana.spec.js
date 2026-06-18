/**
 * @module tests/hana
 * @description Playwright tests for the SAP HANA savepoint detector.
 *
 * The `hana_test-savepoints.zip` fixture is a trimmed slice of a real HANA
 * log bundle: a single `indexserver_test.trc` containing periodic savepoints,
 * replication snapshots, and one real `w Savepoint ... took 12384ms`
 * slow-callback warning line.
 */
import { test, expect } from './coverage-fixture.js';
import { uploadAndWaitForAnalysis, navigateToApp } from './test-helpers.js';

test.describe('SAP HANA savepoints', () => {

  test.beforeEach(async ({ page }, testInfo) => {
    await navigateToApp(page, testInfo);
    await expect(page.locator('h1')).toContainText('RCA Tool');
  });

  test('detects savepoints and flags a slow savepoint callback', async ({ page }) => {
    const html = await uploadAndWaitForAnalysis(page, 'hana_test-savepoints.zip');

    // HANA section and savepoint summary are present.
    expect(html).toContain('SAP HANA Savepoints');
    expect(html).toContain('Periodic savepoints');
    expect(html).toContain('Snapshot savepoints');

    // Slow-callback warning surfaced from the real `took 12384ms` line.
    expect(html).toContain('savepoint callback stalled');
    expect(html).toContain('12.4s');

    // Savepoint event table with a known version from the fixture.
    expect(html).toContain('Savepoint events');
    expect(html).toContain('609685');
  });
});
