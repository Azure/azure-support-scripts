/**
 * @module tests/storage
 * @description Playwright tests for {@link module:parsers/storage}.
 *
 * Tests UUID-mismatch detection between `/etc/fstab` and block
 * devices, LVM configuration parsing from both SCC and sosreport
 * formats, including multi-file accumulation for separate
 * pvs/vgs/lvs files.
 */
import { test, expect } from './coverage-fixture.js';
import { uploadAndWaitForAnalysis, getResultText, navigateToApp } from './test-helpers.js';

test.describe('Storage Parsers', () => {

  test.beforeEach(async ({ page }, testInfo) => {
    await navigateToApp(page, testInfo);
    await expect(page.locator('h1')).toContainText('RCA Tool');
  });

  test('detects and displays LVM configuration from SCC', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'scc_test-lvm.tar.xz');
    
    // Should display LVM Configuration section
    expect(resultHTML).toContain('LVM Configuration');
    
    // Should show Physical Volumes
    expect(resultHTML).toContain('Physical Volumes');
    expect(resultHTML).toContain('/dev/sda2');
    expect(resultHTML).toContain('/dev/sdb1');
    
    // Should show Volume Groups
    expect(resultHTML).toContain('Volume Groups');
    expect(resultHTML).toContain('rootvg');
    expect(resultHTML).toContain('datavg');
    
    // Should show Logical Volumes
    expect(resultHTML).toContain('Logical Volumes');
    expect(resultHTML).toContain('root');
    expect(resultHTML).toContain('swap');
    expect(resultHTML).toContain('app');
    expect(resultHTML).toContain('data');
    expect(resultHTML).toContain('backup');
  });

  test('detects LVM configuration from sosreport verbose format', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'scc_test-lvm-sosreport.tar.xz');

    // Should display LVM Configuration section
    expect(resultHTML).toContain('LVM Configuration');

    // Should detect PVs from separate pvs file (filtering WARNING lines)
    expect(resultHTML).toContain('Physical Volumes');
    expect(resultHTML).toContain('/dev/sda2');
    expect(resultHTML).toContain('/dev/sdc1');
    expect(resultHTML).toContain('/dev/sdd1');

    // Should detect VGs from separate verbose-format vgs file
    expect(resultHTML).toContain('Volume Groups');
    expect(resultHTML).toContain('rootvg');
    expect(resultHTML).toContain('vggridhome');
    expect(resultHTML).toContain('vgoraclebip');

    // Should detect LVs from separate lvs file
    expect(resultHTML).toContain('Logical Volumes');
    expect(resultHTML).toContain('crashlv');
    expect(resultHTML).toContain('rootlv');
    expect(resultHTML).toContain('lvgridhome');
    expect(resultHTML).toContain('lvoraclebip');
  });

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

  test('detects block devices from InspectIaaSDisk results.txt and correlates with fstab', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'test-inspect-iaas-disk-storage.zip');

    // Should parse the Filesystem Status section from results.txt
    // and build a UUID map that enables fstab correlation

    // Should display storage correlation section
    expect(resultHTML).toMatch(/Storage Correlation|UUID|fstab/i);

    // UUIDs present in results.txt should be detected and matched
    expect(resultHTML).toContain('11111111-aaaa-bbbb-cccc-111111111111');

    // Missing UUID from fstab (OLD-UUID-DEAD) should generate an error
    expect(resultHTML).toContain('OLD-UUID-DEAD');

    // Missing UUID (GONE-UUID) should also be flagged
    expect(resultHTML).toContain('GONE-UUID-0000');

    // Should have error badge for UUID not found
    const resultText = await getResultText(page);
    expect(resultText).toMatch(/\[X\].*UUID|UUID.*error|error.*UUID/i);
  });

  test('detects block devices from sosreport lsblk/blkid and correlates with fstab', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'scc_test-sosreport-storage.tar.xz');

    // Should display storage correlation section
    expect(resultHTML).toMatch(/Storage Correlation|UUID|fstab/i);

    // UUIDs present in lsblk/blkid should be detected
    expect(resultHTML).toContain('aaaa1111-1111-1111-1111-aaaaaaaaaaaa');

    // UUID that doesn't exist on disk (DEAD0000) should generate error
    expect(resultHTML).toContain('DEAD0000');

    // fstype mismatch: fstab says ext4, disk (sdc1) has xfs for UUID 5678ef01
    expect(resultHTML).toMatch(/5678ef01.*type.*mismatch|mismatch.*5678ef01|ext4.*xfs|xfs.*ext4/i);

    // Should have error badge for UUID not found
    const resultText = await getResultText(page);
    expect(resultText).toMatch(/\[X\].*UUID|UUID.*error|error.*UUID/i);
  });

  test('detects mtab entries and highlights mounts not in fstab', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'scc_test-mtab-comparison.tar.xz');

    // Should show the mtab section
    expect(resultHTML).toContain('Mounted Filesystems');
    expect(resultHTML).toContain('/etc/mtab');

    // Extra mounts NOT in fstab should be flagged
    expect(resultHTML).toContain('/data');
    expect(resultHTML).toContain('/sapmnt');
    expect(resultHTML).toContain('/hana/data');
    expect(resultHTML).toContain('/hana/log');

    // Should show "not in fstab" badge
    expect(resultHTML).toMatch(/not in fstab/i);

    // Virtual filesystems (sysfs, proc, tmpfs, devtmpfs) should NOT appear as extra mounts
    const resultText = await getResultText(page);
    // The extra mounts table should not contain virtual fs entries
    expect(resultHTML).not.toMatch(/Hand-mounted.*\/sys\b/);
    expect(resultHTML).not.toMatch(/Hand-mounted.*\/proc\b/);

    // Should show raw mtab content
    expect(resultHTML).toContain('Show raw /etc/mtab');

    // SAP/HANA mounts should be identified as likely cluster-managed
    expect(resultHTML).toMatch(/cluster-managed/i);
  });
});
