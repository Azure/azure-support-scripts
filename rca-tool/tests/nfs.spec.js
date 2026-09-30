/**
 * @module tests/nfs
 * @description Playwright tests for the NFS mount-option detector.
 *
 * The `scc_test-nfs-mounts.tar.xz` fixture contains an `/etc/fstab` with two
 * SAP/HANA NFS mounts that use sub-optimal options (soft, small rsize/wsize,
 * NFSv4.0) and one correctly-tuned mount (hard, 256 KiB sizes, nconnect=8,
 * NFSv4.1) that should produce no warnings.
 */
import { test, expect } from './coverage-fixture.js';
import { uploadAndWaitForAnalysis, navigateToApp } from './test-helpers.js';

test.describe('NFS mount options', () => {

  test.beforeEach(async ({ page }, testInfo) => {
    await navigateToApp(page, testInfo);
    await expect(page.locator('h1')).toContainText('RCA Tool');
  });

  test('flags soft mounts, small rsize/wsize, and outdated NFS version', async ({ page }) => {
    const html = await uploadAndWaitForAnalysis(page, 'scc_test-nfs-mounts.tar.xz');

    // NFS subsection and mount table are present.
    expect(html).toContain('NFS Mounts');
    expect(html).toContain('/hana/data');
    expect(html).toContain('/hana/log');
    expect(html).toContain('/sapmnt');

    // soft-mount error.
    expect(html).toContain("uses the 'soft' option");

    // small rsize/wsize warning.
    expect(html).toContain('small read/write sizes');

    // outdated protocol version warning (NFSv4.0).
    expect(html).toContain('uses protocol version 4.0');

    // The well-tuned /sapmnt mount uses NFSv4.1 with hard + nconnect.
    expect(html).toContain('4.1');
  });
});
