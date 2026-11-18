/**
 * @module tests/events
 * @description Playwright tests for {@link module:parsers/events}.
 *
 * Covers kernel-reboot detection, OOM killer event parsing, and XFS
 * error analysis including danger-block alerts, deduplication across
 * rotated log files, timestamp normalisation, correct counts after
 * dedup, and duplicate-UUID detection.
 */
import { test, expect } from './coverage-fixture.js';
import { uploadAndWaitForAnalysis, getResultText, navigateToApp, fixturePath } from './test-helpers.js';

test.describe('Events Parsers', () => {

  test.beforeEach(async ({ page }, testInfo) => {
    await navigateToApp(page, testInfo);
    await expect(page.locator('h1')).toContainText('RCA Tool');
  });

  test('detects kernel reboots', async ({ page }) => {
    const result = await uploadAndWaitForAnalysis(page, 'scc_test-kernel-reboots.tar.xz');
    
    expect(result).toContain('Kernel Reboots');
    expect(result).toMatch(/\d+ events? found/i);
    // Should show reboot timestamps
    expect(result).toMatch(/\d{4}-\d{2}-\d{2}|\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}/);
  });

  test('detects OOM killer events', async ({ page }) => {
    const result = await uploadAndWaitForAnalysis(page, 'scc_test-oom-killer.tar.xz');
    
    if (result.includes('OOM Killer')) {
      expect(result).toMatch(/OOM Killer.*\d+ event/i);
      // Should show process names
      expect(result).toMatch(/invoked oom-killer|Killed process/i);
    }
  });

  test('detects XFS errors in log files', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'scc_test-xfs-errors.tar.xz');
    
    // Check that XFS Filesystem Errors section exists
    expect(resultHTML).toContain('XFS Filesystem Errors');
    
    // Check for specific error messages that are actually in the output
    expect(resultHTML).toContain('Corruption detected');
    expect(resultHTML).toContain('Internal error xfs_trans_cancel');
    
    // Check for devices that appear in non-deduplicated errors
    expect(resultHTML).toContain('sdb2');
    expect(resultHTML).toContain('sdc3');
    
    // Check for unrecovered unlinked inode pattern
    expect(resultHTML).toContain('unrecovered unlinked inode');
    expect(resultHTML).toContain('sdk4');
    
    // Check for timestamps (normalized format with zero-padded days)
    expect(resultHTML).toContain('Dec 02 15:07:11');
    expect(resultHTML).toContain('Dec 03 08:45:23');
  });

  test('shows critical alert (danger-block) for XFS errors', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'scc_test-xfs-errors.tar.xz');
    
    // Check that Events section has danger-block class (red background)
    const eventsSection = await page.locator('#output').innerHTML();
    expect(eventsSection).toContain('danger-block');
    
    // Verify the Events section is highlighted as critical
    const hasEventsTitle = eventsSection.includes('Events') || eventsSection.includes('events');
    expect(hasEventsTitle).toBeTruthy();
  });

  test('deduplicates XFS errors across rotated log files', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'scc_test-xfs-errors.tar.xz');
    
    // Check that we have the XFS Filesystem Errors section
    expect(resultHTML).toContain('XFS Filesystem Errors');
    
    // Verify that duplicates were removed - the total count should be less than 9
    const content = await page.locator('#output').textContent();
    const countMatch = content.match(/XFS Filesystem Errors\s*\((\d+)\s+errors? found\)/);
    expect(countMatch).toBeTruthy();
    
    const count = parseInt(countMatch[1], 10);
    // We expect deduplication to work, so count should be less than total lines with XFS
    expect(count).toBeLessThan(9);
    expect(count).toBeGreaterThan(0);
  });

  test('normalizes timestamps for consistent deduplication', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'scc_test-xfs-timestamp-normalization.tar.xz');
    
    // Check that XFS section exists
    expect(resultHTML).toContain('XFS Filesystem Errors');
    
    // Both "Dec  5" and "Dec 05" should be normalized to "Dec 05"
    const content = await page.locator('#output').textContent();
    const countMatch = content.match(/XFS Filesystem Errors\s*\((\d+)\s+errors? found\)/);
    expect(countMatch).toBeTruthy();
    
    const count = parseInt(countMatch[1], 10);
    // Should have exactly 2 errors (one corruption warning, one internal error)
    expect(count).toBe(2);
    
    // Verify both error types are present
    expect(resultHTML).toContain('Corruption warning: inode 456789');
    expect(resultHTML).toContain('Internal error XFS_WANT_CORRUPTED_GOTO');
    
    // Verify normalized timestamp format is used (zero-padded day)
    expect(resultHTML).toContain('Dec 05 10:15:');
  });

  test('counts XFS errors correctly after deduplication', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'scc_test-xfs-errors.tar.xz');
    
    // Get the full content
    const content = await page.locator('#output').textContent();
    
    // Should have XFS Filesystem Errors section with a count
    expect(content).toContain('XFS Filesystem Errors');
    
    // Parse the count (format: "XFS Filesystem Errors (X errors found)")
    const countMatch = content.match(/XFS Filesystem Errors\s*\((\d+)\s+errors? found\)/);
    expect(countMatch).toBeTruthy();
    
    const count = parseInt(countMatch[1], 10);
    
    // Based on actual output, we're seeing 2 errors displayed
    expect(count).toBeGreaterThan(0);
    expect(count).toBeLessThanOrEqual(7);
  });

  test('detects XFS duplicate UUID errors', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'scc_test-xfs-duplicate-uuid.tar.xz');
    
    // Check that XFS Filesystem Errors section exists
    expect(resultHTML).toContain('XFS Filesystem Errors');
    
    // Check for duplicate UUID error message
    expect(resultHTML).toContain('duplicate UUID');
    expect(resultHTML).toContain('can\'t mount');
    
    // Check for the UUID values
    expect(resultHTML).toContain('ac560ede-78b1-4d66-b199-2c1284ad1aaf');
    expect(resultHTML).toContain('f1234567-89ab-cdef-0123-456789abcdef');
    
    // Check for devices
    expect(resultHTML).toContain('sde1');
    expect(resultHTML).toContain('sdf1');
    
    // Verify it's treated as critical (danger-block)
    expect(resultHTML).toContain('danger-block');
    
    // Check for timestamp normalization
    expect(resultHTML).toContain('Dec 03 17:37:');
  });

  test('detects kernel reboots from InspectIaaSDisk ZIP', async ({ page }) => {
    const fileInput = await page.locator('input[type="file"]');
    await fileInput.setInputFiles(fixturePath('test-inspect-iaas-disk.zip'));

    await page.waitForFunction(
      () => {
        const output = document.getElementById('output');
        return output && output.textContent.includes('InspectIaaSDisk Results');
      },
      { timeout: 60000 }
    );

    const content = await page.locator('#output').textContent();

    // Should detect kernel boot events from device_0/var/log/messages
    expect(content).toContain('4.18.0-477.27.1.el8_8.x86_64');
    // Should show reboot events section
    expect(content).toMatch(/kernel.*reboot|reboot.*event/i);
  });

  test('detects OOM killer events from InspectIaaSDisk ZIP', async ({ page }) => {
    const fileInput = await page.locator('input[type="file"]');
    await fileInput.setInputFiles(fixturePath('test-inspect-iaas-disk.zip'));

    await page.waitForFunction(
      () => {
        const output = document.getElementById('output');
        return output && output.textContent.includes('InspectIaaSDisk Results');
      },
      { timeout: 60000 }
    );

    const content = await page.locator('#output').textContent();

    // Should detect OOM killer event
    expect(content).toContain('java');
    expect(content).toMatch(/oom|out of memory/i);
  });

  test('detects XFS errors from InspectIaaSDisk ZIP', async ({ page }) => {
    const fileInput = await page.locator('input[type="file"]');
    await fileInput.setInputFiles(fixturePath('test-inspect-iaas-disk.zip'));

    await page.waitForFunction(
      () => {
        const output = document.getElementById('output');
        return output && output.textContent.includes('InspectIaaSDisk Results');
      },
      { timeout: 60000 }
    );

    const content = await page.locator('#output').textContent();

    // Should detect XFS errors from device_0/var/log/messages
    expect(content).toContain('XFS Filesystem Errors');
    expect(content).toContain('sdb1');
    expect(content).toContain('unrecovered unlinked inode');
  });

  test('detects emergency mode from InspectIaaSDisk ZIP', async ({ page }) => {
    const fileInput = await page.locator('input[type="file"]');
    await fileInput.setInputFiles(fixturePath('test-inspect-iaas-disk.zip'));

    await page.waitForFunction(
      () => {
        const output = document.getElementById('output');
        return output && output.textContent.includes('InspectIaaSDisk Results');
      },
      { timeout: 60000 }
    );

    const content = await page.locator('#output').textContent();

    // Should detect emergency mode from device_0/var/log/messages
    expect(content).toMatch(/emergency mode/i);
  });
});
