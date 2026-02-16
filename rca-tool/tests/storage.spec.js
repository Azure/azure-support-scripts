/**
 * @module tests/storage
 * @description Playwright tests for {@link module:parsers/storage}.
 *
 * Tests UUID-mismatch detection between `/etc/fstab` and block
 * devices.  Also contains commented-out tests for LVM, RAID, BTRFS,
 * and PV-validation that are pending a storage.js loading fix.
 */
import { test, expect } from '@playwright/test';
import { uploadAndWaitForAnalysis, getResultText, navigateToApp } from './test-helpers.js';

test.describe('Storage Parsers', () => {

  test.beforeEach(async ({ page }, testInfo) => {
    await navigateToApp(page, testInfo);
    await expect(page.locator('h1')).toContainText('RCA Tool');
  });

  // TODO: Re-enable these tests when storage.js loading issue is fixed
  /*
  test('detects and displays LVM configuration', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'scc_test-lvm.tar.xz');
    
    // Should display LVM Configuration section
    expect(resultHTML).toContain('LVM Configuration');
    
    // Should show Physical Volumes
    expect(resultHTML).toContain('Physical Volumes');
    expect(resultHTML).toContain('/dev/sda2');
    expect(resultHTML).toContain('/dev/sdb1');
    expect(resultHTML).toContain('/dev/sdc1');
    
    // Should show Volume Groups
    expect(resultHTML).toContain('Volume Groups');
    expect(resultHTML).toContain('rootvg');
    expect(resultHTML).toContain('datavg');
    expect(resultHTML).toContain('missingvg');
    
    // Should show Logical Volumes
    expect(resultHTML).toContain('Logical Volumes');
    expect(resultHTML).toContain('root');
    expect(resultHTML).toContain('swap');
    expect(resultHTML).toContain('app');
    expect(resultHTML).toContain('data');
    expect(resultHTML).toContain('backup');
    
    // Should display warnings for missing PVs
    expect(resultHTML).toContain('warning');
    
    // Should show raw output sections
    expect(resultHTML).toContain('Raw pvs output');
    expect(resultHTML).toContain('Raw vgs output');
    expect(resultHTML).toContain('Raw lvs output');
  });

  test('detects and displays RAID configuration', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'scc_test-raid.tar.xz');
    
    // Should display RAID Configuration section
    expect(resultHTML).toContain('RAID Configuration');
    
    // Should show RAID Arrays
    expect(resultHTML).toContain('RAID Arrays');
    expect(resultHTML).toContain('md0');
    expect(resultHTML).toContain('md1');
    expect(resultHTML).toContain('md2');
    
    // Should display RAID levels
    expect(resultHTML).toContain('raid1');
    expect(resultHTML).toContain('raid5');
    
    // Should show device status
    expect(resultHTML).toContain('ACTIVE');
    expect(resultHTML).toContain('/dev/sda1');
    expect(resultHTML).toContain('/dev/sdb1');
    expect(resultHTML).toContain('/dev/sdc1');
    
    // Should display warnings for degraded arrays
    expect(resultHTML).toContain('DEGRADED');
    
    // Should show faulty devices
    expect(resultHTML).toContain('faulty');
    
    // Should show raw mdstat output
    expect(resultHTML).toContain('Raw /proc/mdstat');
  });

  test('detects and displays BTRFS configuration', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'scc_test-btrfs.tar.xz');
    
    // Should display BTRFS Configuration section
    expect(resultHTML).toContain('BTRFS Configuration');
    
    // Should show BTRFS Filesystems
    expect(resultHTML).toContain('BTRFS Filesystems');
    expect(resultHTML).toContain('root');
    expect(resultHTML).toContain('data');
    expect(resultHTML).toContain('550e8400-e29b-41d4-a716-446655440000');
    expect(resultHTML).toContain('7a8b9c0d-1e2f-3a4b-5c6d-7e8f9a0b1c2d');
    
    // Should show devices
    expect(resultHTML).toContain('/dev/sda2');
    expect(resultHTML).toContain('/dev/sdb2');
    expect(resultHTML).toContain('/dev/sdc1');
    expect(resultHTML).toContain('/dev/sdd1');
    expect(resultHTML).toContain('/dev/sde1');
    
    // Should show BTRFS Subvolumes
    expect(resultHTML).toContain('BTRFS Subvolumes');
    expect(resultHTML).toContain('@rootfs');
    expect(resultHTML).toContain('@home');
    expect(resultHTML).toContain('@var');
    expect(resultHTML).toContain('@var/log');
    expect(resultHTML).toContain('@snapshots');
    
    // Should show raw output sections
    expect(resultHTML).toContain('Raw btrfs filesystem show');
    expect(resultHTML).toContain('Raw btrfs subvolume list');
  });

  test('validates PV presence in VGs', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'scc_test-lvm.tar.xz');
    
    // Should detect missing PVs in missingvg
    expect(resultHTML).toContain('missingvg');
    
    // Should show warning for PARTIAL status
    const resultText = await getResultText(page);
    expect(resultText).toMatch(/partial|missing|warning/i);
    
    // Should properly parse PV counts
    expect(resultHTML).toMatch(/#PV/);
  });
  */

  test('detects UUID mismatches between fstab and block devices', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'scc_test-block-devices-mismatch.tar.xz');
    
    // Should display storage correlation section
    expect(resultHTML).toMatch(/Storage Correlation|UUID|fstab/i);
    
    // Should show error for UUIDs in fstab that don't exist on disk
    expect(resultHTML).toContain('OLD-UUID-3333');
    expect(resultHTML).toContain('MISSING-UUID-9999');
    
    // Should show warnings for filesystem type mismatches
    // fstab says ext4 but disk has xfs for UUID 66666666-6666-6666-6666-666666666666
    expect(resultHTML).toMatch(/66666666.*type.*mismatch|mismatch.*66666666|ext4.*xfs|xfs.*ext4/i);
    
    // Should have error badge or indicator in summary
    const resultText = await getResultText(page);
    expect(resultText).toMatch(/\[X\].*UUID|UUID.*error|error.*UUID/i);
  });
});
