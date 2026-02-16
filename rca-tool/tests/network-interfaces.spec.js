/**
 * @module tests/network-interfaces
 * @description Playwright tests for {@link module:parsers/network-interfaces}.
 *
 * Verifies network-interface detection from SCC `network.txt`
 * (eth0/eth1, DHCP vs static, mlx5_core accelerated networking) and
 * SOS reports (MANA driver, DHCP configuration).
 */
import { test, expect } from './coverage-fixture.js';
import { uploadAndWaitForAnalysis, getResultText, navigateToApp } from './test-helpers.js';

test.describe('Network Interfaces Parser', () => {

  test.beforeEach(async ({ page }, testInfo) => {
    await navigateToApp(page, testInfo);
    await expect(page.locator('h1')).toContainText('RCA Tool');
  });

  test('detects interfaces, DHCP/static, and accelerated networking from SCC network.txt', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'scc_test-network-interfaces-scc.tar.xz');
    const resultText = await getResultText(page);

    // Should show Networking section with Network Interfaces sub-section
    expect(resultHTML).toContain('Networking');
    expect(resultHTML).toContain('Network Interfaces');
    // Should detect eth0 and eth1
    expect(resultHTML).toContain('eth0');
    expect(resultHTML).toContain('eth1');
    // Should show IP address
    expect(resultHTML).toContain('10.0.0.4');
    // Should show DHCP for eth0
    expect(resultHTML).toContain('DHCP');
    // Should show Static for eth1
    expect(resultHTML).toContain('Static');
    // Should detect accelerated networking via mlx5_core on eth1
    expect(resultHTML).toContain('mlx5_core');
    // Should show hv_netvsc driver for eth0
    expect(resultHTML).toContain('hv_netvsc');
    // Should show Accelerated Networking label
    expect(resultHTML).toMatch(/Accelerated Networking/i);
  });

  test('detects MANA driver and DHCP from SOS report', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'scc_test-network-interfaces-sos-mana.tar.xz');
    const resultText = await getResultText(page);

    // Should show Network Interfaces
    expect(resultHTML).toContain('Network Interfaces');
    // Should detect eth0
    expect(resultHTML).toContain('eth0');
    // Should detect enP30832s1 (MANA interface)
    expect(resultHTML).toContain('enP30832s1');
    // Should detect MANA driver
    expect(resultHTML).toContain('mana');
    expect(resultHTML).toContain('MANA');
    // Should show DHCP for eth0
    expect(resultHTML).toContain('DHCP');
    // Should show IP
    expect(resultHTML).toContain('10.1.0.5');
    // Should show accelerated networking
    expect(resultHTML).toMatch(/Accelerated Networking/i);
  });
});
