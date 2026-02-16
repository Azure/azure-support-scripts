/**
 * @module tests/networking
 * @description Playwright tests for {@link module:parsers/networking}.
 *
 * Tests firewall-rule detection from SOS reports (nftables active,
 * firewalld active) and SCC archives (no active firewall, nftables
 * in `network.txt`).
 */
import { test, expect } from './coverage-fixture.js';
import { uploadAndWaitForAnalysis, getResultText, navigateToApp } from './test-helpers.js';

test.describe('Networking Parser', () => {

  test.beforeEach(async ({ page }, testInfo) => {
    await navigateToApp(page, testInfo);
    await expect(page.locator('h1')).toContainText('RCA Tool');
  });

  test('detects firewall rules from SOS report with nftables active', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'scc_test-firewall-sosreport.tar.xz');
    const resultText = await getResultText(page);

    // Should show the Networking section
    expect(resultHTML).toContain('Networking');
    // Should show the Firewall Rules sub-section
    expect(resultHTML).toContain('Firewall Rules');
    // Should detect nftables as active (firewalld not running, nftables has rules)
    expect(resultText).toMatch(/nftables|Active.*nftables/i);
    // Should show waagent security rules (168.63.129.16)
    expect(resultHTML).toContain('168.63.129.16');
  });

  test('detects firewall rules from SOS report with firewalld active', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'scc_test-firewall-sosreport-active.tar.xz');
    const resultText = await getResultText(page);

    // Should show Networking section with Firewall Rules
    expect(resultHTML).toContain('Networking');
    expect(resultHTML).toContain('Firewall Rules');
    // Should detect firewalld as active
    expect(resultText).toMatch(/firewalld|Active.*firewalld/i);
    // Should show firewalld is running
    expect(resultHTML).toMatch(/running/i);
  });

  test('detects no active firewall from SCC report', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'scc_test-firewall-scc.tar.xz');
    const resultText = await getResultText(page);

    // Should show Networking section with Firewall Rules
    expect(resultHTML).toContain('Networking');
    expect(resultHTML).toContain('Firewall Rules');
    // Should indicate no active firewall
    expect(resultText).toMatch(/No Active Firewall/i);
  });

  test('detects nftables from SCC network.txt', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'scc_test-firewall-scc-nftables.tar.xz');
    const resultText = await getResultText(page);

    // Should show Networking section
    expect(resultHTML).toContain('Networking');
    expect(resultHTML).toContain('Firewall Rules');
    // Should detect nftables as active
    expect(resultText).toMatch(/nftables|Active.*nftables/i);
    // Should show the security table with waagent rules
    expect(resultHTML).toContain('168.63.129.16');
  });
});
