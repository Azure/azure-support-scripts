/**
 * @module tests/packages
 * @description Playwright tests for {@link module:parsers/packages}.
 *
 * Validates raw package-list rendering for RPM-based distributions
 * (`dnf_list_installed`, `yum_list_installed`) and Debian-based
 * distributions (`dpkg_-l`).
 */
import { test, expect } from './coverage-fixture.js';
import { uploadAndWaitForAnalysis, navigateToApp } from './test-helpers.js';

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
});
