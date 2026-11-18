/**
 * @module tests/vmcore
 * @description Playwright tests for {@link module:parsers/vmcore}.
 *
 * Validates vmcore crash-dump detection from sosreports: crash count
 * badge, kdump operational status, panic reasons, crash dates,
 * kernel versions, call-trace frames, vmcore sizes and disk usage,
 * kdump configuration, and documentation links.
 */
import { test, expect } from './coverage-fixture.js';
import { uploadAndWaitForAnalysis, navigateToApp } from './test-helpers.js';

test.describe('Vmcore Parser', () => {

  test.beforeEach(async ({ page }, testInfo) => {
    await navigateToApp(page, testInfo);
    await expect(page.locator('h1')).toContainText('RCA Tool');
  });

  test('detects vmcore crash dumps from sosreport', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'scc_test-vmcore-crashes.tar.xz');

    // Should show Kernel Crash Dumps section
    expect(resultHTML).toContain('Kernel Crash Dumps');
    // Should show the crash count badge
    expect(resultHTML).toContain('2 vmcores');

    // Should show kdump status
    expect(resultHTML).toContain('Kdump is operational');

    // Should show panic reason
    expect(resultHTML).toContain('hung_task: blocked tasks');

    // Should show crash dates
    expect(resultHTML).toContain('2026-02-13');
    expect(resultHTML).toContain('2025-10-05');

    // Should show kernel versions
    expect(resultHTML).toContain('4.18.0-553.89.1.el8_10.x86_64');
    expect(resultHTML).toContain('4.18.0-553.75.1.el8_10.x86_64');

    // Should show process names
    expect(resultHTML).toContain('khungtaskd');

    // Should show call trace frames
    expect(resultHTML).toContain('dump_stack');
    expect(resultHTML).toContain('watchdog');

    // Should show vmcore sizes from listing
    expect(resultHTML).toMatch(/GB|MB/);

    // Should show total disk usage
    expect(resultHTML).toContain('Total vmcore disk usage');

    // Should show kdump configuration
    expect(resultHTML).toContain('Kdump Configuration');
    expect(resultHTML).toContain('/var/crash');

    // Should link to documentation
    expect(resultHTML).toContain('troubleshoot-kdump');
  });

  test('handles edge cases: no-date crash, empty kdump status, empty listing', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'scc_test-vmcore-edge-cases.tar.xz');

    // Should still detect kernel crash dumps
    expect(resultHTML).toContain('Kernel Crash Dumps');

    // Should show 2 crashes (one with date, one without)
    expect(resultHTML).toContain('2 vmcores');

    // Crash without date in directory path (nodate-crash) — covers null date sort guards
    expect(resultHTML).toContain('VFS: Unable to mount root fs');

    // Crash with valid date — covers dated crash + sort with null-date crash
    expect(resultHTML).toContain('Fatal exception in interrupt');
    expect(resultHTML).toContain('2026-01-20');

    // Call trace from no-timestamp dmesg terminated by ---[ end ... ]--- line
    expect(resultHTML).toContain('mount_block_root');
    expect(resultHTML).toContain('kernel_init');

    // Empty kdump status → parseKdumpStatus returns null, no status shown
    expect(resultHTML).not.toContain('Kdump is operational');

    // Empty crash listing → parseCrashListing returns null, no sizes shown
    expect(resultHTML).not.toContain('Total vmcore disk usage');

    // kdump.conf should still be parsed
    expect(resultHTML).toContain('Kdump Configuration');
    expect(resultHTML).toContain('/var/crash');

    // failure_action = reboot (using 'default' keyword in conf)
    expect(resultHTML).toContain('reboot');
  });
});
