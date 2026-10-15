/**
 * @module tests/packages
 * @description Playwright tests for {@link module:parsers/packages}.
 *
 * Validates raw package-list rendering for RPM-based distributions
 * (`dnf_list_installed`, `yum_list_installed`), Debian-based
 * distributions (`dpkg_-l`), zypper history, and dnf/yum logs.
 */
import { test, expect } from './coverage-fixture.js';
import { uploadAndWaitForAnalysis, navigateToApp, fixturePath } from './test-helpers.js';

test.describe('Packages Parser', () => {

  test.beforeEach(async ({ page }, testInfo) => {
    await navigateToApp(page, testInfo);
    await expect(page.locator('h1')).toContainText('RCA Tool');
  });

  test('displays raw RPM package list from dnf_list_installed', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'sosreport-rpm-raw.tar.xz');
    
    // Should show Distribution section with package content
    expect(resultHTML).toContain('Distribution');
    
    // Should display package names from dnf list
    expect(resultHTML).toContain('GConf2');
    expect(resultHTML).toContain('NetworkManager');
    expect(resultHTML).toContain('PackageKit');
    
    // Should show package count in subsection header
    expect(resultHTML).toMatch(/Packages \(\d+ RPM-based\)/i);
  });

  test('displays raw RPM package list from yum_list_installed', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'sosreport-yum-raw.tar.xz');
    
    // Should show Distribution section with package content
    expect(resultHTML).toContain('Distribution');
    
    // Should display package names from yum list
    expect(resultHTML).toContain('BladeLogic_RSCD_Agent');
    expect(resultHTML).toContain('GConf2');
    expect(resultHTML).toContain('NetworkManager');
    
    // Should show package count in subsection header
    expect(resultHTML).toMatch(/Packages \(\d+ RPM-based\)/i);
    
    // Should handle yum plugin headers
    expect(resultHTML).not.toContain('Loaded plugins');
  });

  test('displays raw DEB package list from dpkg_-l', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'sosreport-deb-raw.tar.xz');
    
    // Should show Distribution section with package content
    expect(resultHTML).toContain('Distribution');
    
    // Should display package names from dpkg
    expect(resultHTML).toContain('accountsservice');
    expect(resultHTML).toContain('bash');
    expect(resultHTML).toContain('systemd');
    
    // Should show package count in subsection header
    expect(resultHTML).toMatch(/Packages \(\d+ Debian\/Ubuntu\)/i);
  });

  test('displays SUSE supportconfig rpm.txt with section parsing', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'sosreport-rpm-txt-scc.tar.xz');

    // Should show Distribution section
    expect(resultHTML).toContain('Distribution');

    // Should display packages from the filtered section (between queryformat headers)
    expect(resultHTML).toContain('cloud-netconfig-azure');
    expect(resultHTML).toContain('resource-agents');
    expect(resultHTML).toContain('fence-agents');
    expect(resultHTML).toContain('kernel-default');

    // Should show RPM-based package count
    expect(resultHTML).toMatch(/Packages \(\d+ RPM-based\)/i);

    // Should NOT include content from the SIGPGP section (after the second header)
    expect(resultHTML).not.toContain('some-other-section-data');
  });

  test('validates RPM package versions from installed-rpms', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'sosreport-installed-rpms.tar.xz');

    // Should show Distribution section
    expect(resultHTML).toContain('Distribution');

    // Should show version warnings for fence-agents (4.2.1 < 4.4 required)
    expect(resultHTML).toContain('fence-agents');
    expect(resultHTML).toContain('4.2.1');

    // Should show problematic range warning for python3-azure-core (1.15.0 is in 1.9-1.22 range)
    expect(resultHTML).toContain('python3-azure-core');
    expect(resultHTML).toContain('1.15.0');

    // Should flag missing package: cloud-netconfig-azure not in the RPM list
    expect(resultHTML).toContain('cloud-netconfig-azure');
    expect(resultHTML).toContain('not found');

    // Found packages should be listed
    expect(resultHTML).toContain('python3-azure-mgmt-compute');
    expect(resultHTML).toContain('python3-azure-identity');
    expect(resultHTML).toContain('resource-agents');
  });

  test('detects packages from zypper history in InspectIaaSDisk SUSE cluster ZIP', async ({ page }) => {
    const fileInput = await page.locator('input[type="file"]');
    await fileInput.setInputFiles(fixturePath('test-inspect-iaas-disk-cluster.zip'));

    await page.waitForFunction(
      () => {
        const output = document.getElementById('output');
        return output && output.textContent.includes('InspectIaaSDisk Results');
      },
      { timeout: 60000 }
    );

    const content = await page.locator('#output').textContent();

    // Should show Distribution/Packages section with RPM-based label
    expect(content).toMatch(/Packages \(\d+ RPM-based\)/i);

    // Should detect Azure-critical packages from zypper history
    expect(content).toContain('fence-agents-azure-arm');
    expect(content).toContain('resource-agents');
    expect(content).toContain('cloud-netconfig-azure');
    expect(content).toContain('python3-azure-mgmt-compute');

    // python3-azure-core 1.22.1 is in problematic range (1.9-1.22) — should trigger warning
    expect(content).toContain('python3-azure-core');
    expect(content).toContain('1.22.1');
  });

  test('detects packages from dnf.log in InspectIaaSDisk RHEL ZIP', async ({ page }) => {
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

    // Should show Distribution/Packages section
    expect(content).toMatch(/Packages \(\d+ RPM-based\)/i);

    // Should detect packages from dnf.log install records
    expect(content).toContain('fence-agents-azure-arm');
    expect(content).toContain('resource-agents');
    expect(content).toContain('python3-azure-mgmt-compute');
    expect(content).toContain('python3-azure-identity');
    expect(content).toContain('python3-azure-core');
  });
});
