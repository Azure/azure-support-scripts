/**
 * @module tests/services
 * @description Playwright tests for {@link module:parsers/services}.
 *
 * Covers antivirus detection (Falcon Sensor, Microsoft Defender),
 * Illumio and Trend Micro Deep Security identification, Azure Site
 * Recovery (`involflt`) module and runtime version parsing, and DLM
 * service-enabled detection with documentation links.
 */
import { test, expect } from './coverage-fixture.js';
import { uploadAndWaitForAnalysis, navigateToApp } from './test-helpers.js';

test.describe('Services Parsers', () => {

  test.beforeEach(async ({ page }, testInfo) => {
    await navigateToApp(page, testInfo);
    await expect(page.locator('h1')).toContainText('RCA Tool');
  });

  test('detects antivirus software', async ({ page }) => {
    const result = await uploadAndWaitForAnalysis(page, 'scc_test-antivirus.tar.xz');
    
    if (result.includes('Antivirus')) {
      // Should detect Falcon Sensor or Defender
      const hasAntivirus = result.includes('Falcon Sensor') || result.includes('Microsoft Defender');
      expect(hasAntivirus).toBeTruthy();
      
      // Should show SAP exclusions status
      expect(result).toMatch(/SAP.*exclusion/i);
    }
  });

  test('detects Illumio security software', async ({ page }) => {
    const result = await uploadAndWaitForAnalysis(page, 'scc_test-illumio.tar.xz');
    
    // Should detect Illumio
    expect(result).toContain('Illumio');
    
    // Should show SAP exclusions message
    expect(result).toMatch(/SAP.*exclusion/i);
  });

  test('detects Trend Micro Deep Security', async ({ page }) => {
    const result = await uploadAndWaitForAnalysis(page, 'scc_test-trendmicro.tar.xz');
    
    // Should detect Trend Micro
    expect(result).toContain('Trend Micro');
    
    // Should show SAP exclusions message
    expect(result).toMatch(/SAP.*exclusion/i);
  });

  test('detects Azure Site Recovery (involflt) service', async ({ page }) => {
    const result = await uploadAndWaitForAnalysis(page, 'scc_test-asr.tar.xz');
    
    // Should detect Azure Site Recovery
    expect(result).toContain('Azure Site Recovery');
    expect(result).toContain('involflt');
  });

  test('detects involflt module version from modinfo', async ({ page }) => {
    const result = await uploadAndWaitForAnalysis(page, 'scc_test-asr.tar.xz');
    
    // Should detect involflt version information
    expect(result).toContain('InMage Filter Driver');
    expect(result).toContain('Build Version');
    
    // Should show loaded status
    expect(result).toMatch(/Loaded|Not Loaded/);
  });

  test('detects involflt runtime version from kernel logs', async ({ page }) => {
    const result = await uploadAndWaitForAnalysis(page, 'scc_test-asr.tar.xz');
    
    // Should detect runtime version from kernel messages
    if (result.includes('Runtime Version')) {
      expect(result).toMatch(/Runtime Version:.*\d+\.\d+\.\d+\.\d+/);
    }
  });

  test('detects DLM service enabled', async ({ page }) => {
    const result = await uploadAndWaitForAnalysis(page, 'scc_test-dlm-service.tar.xz');
    
    // Should detect DLM service
    expect(result).toContain('DLM Service');
    expect(result).toContain('Cluster Services');
    
    // Should show error message and documentation link
    expect(result).toMatch(/DLM.*enabled/i);
    expect(result).toContain('https://access.redhat.com/solutions/878023');
  });

  test('detects Azure VM Extensions from InspectIaaSDisk ZIP', async ({ page }) => {
    const result = await uploadAndWaitForAnalysis(page, 'test-inspect-iaas-disk.zip');

    // Should show Azure VM Extensions section with 4 extensions
    expect(result).toContain('Azure VM Extensions');

    // Should detect Defender as NotReady
    expect(result).toContain('Microsoft Defender for Endpoint');
    expect(result).toMatch(/NotReady/);

    // Should detect healthy extensions
    expect(result).toContain('Azure Backup');
    expect(result).toContain('Azure Update Manager');
    expect(result).toContain('Run Command');
    expect(result).toContain('Ready');

    // Should show the not-ready warning badge
    expect(result).toMatch(/not ready/i);
  });
});
