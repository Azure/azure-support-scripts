/**
 * @module tests/hana-trace-events
 * @description Playwright tests for the SAP HANA trace-event detectors:
 * deadlocks, out-of-memory (OOM), and delta-merge / optimize-compression
 * failures.
 *
 * The `hana_test-trace-events.zip` fixture is a trimmed slice of a real HANA
 * indexserver alert trace: several `Lock ... Deadlock detected` cycles, one
 * full `OUT OF MEMORY occurred` block (GLOBAL_ALLOCATION_LIMIT), and a series
 * of `e delta_merge` / `e optimize_compres` failures (most with rc = 2465,
 * merge-token exhaustion).
 */
import { test, expect } from './coverage-fixture.js';
import { uploadAndWaitForAnalysis, navigateToApp } from './test-helpers.js';

test.describe('SAP HANA trace events', () => {

  test.beforeEach(async ({ page }, testInfo) => {
    await navigateToApp(page, testInfo);
    await expect(page.locator('h1')).toContainText('RCA Tool');
  });

  test('detects deadlocks, OOM and delta-merge failures', async ({ page }) => {
    const html = await uploadAndWaitForAnalysis(page, 'hana_test-trace-events.zip');

    // --- Deadlocks ---
    expect(html).toContain('SAP HANA Deadlocks');
    expect(html).toContain('Deadlocks detected');
    expect(html).toContain('deadlock(s) detected');
    // Most contended object from the real cycles.
    expect(html).toContain('SAPHANADB:ADR2');

    // --- Out-of-memory ---
    expect(html).toContain('SAP HANA Out-of-Memory');
    expect(html).toContain('Out-of-memory events');
    expect(html).toContain('vmltmdbuspd01');
    expect(html).toContain('GLOBAL_ALLOCATION_LIMIT');

    // --- Delta-merge / compression failures ---
    expect(html).toContain('SAP HANA Delta-Merge Failures');
    expect(html).toContain('Merge-token exhaustion');
    expect(html).toContain('delta-merge / compression failure');
  });
});
