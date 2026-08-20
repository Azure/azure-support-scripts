/**
 * @module tests/network-interfaces
 * @description Playwright tests for {@link module:parsers/network-interfaces}.
 *
 * Verifies network-interface detection from SCC `network.txt`
 * (eth0/eth1, DHCP vs static, mlx5_core accelerated networking) and
 * SOS reports (MANA driver, DHCP configuration).
 */
import { test, expect } from './coverage-fixture.js';
import { uploadAndWaitForAnalysis, getResultText, navigateToApp, fixturePath } from './test-helpers.js';

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

  test('detects network interfaces from ifcfg files in InspectIaaSDisk ZIP', async ({ page }) => {
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

    // Should detect eth0 and eth1 from ifcfg files
    expect(content).toContain('eth0');
    expect(content).toContain('eth1');
    // Should detect DHCP for eth0
    expect(content).toMatch(/dhcp/i);
    // Should detect static IP for eth1
    expect(content).toContain('10.0.0.50');
    // Should detect DHCP IP from cloud-init ci-info (latest boot only)
    expect(content).toContain('10.0.0.4');
    // Should NOT show old boot IP
    expect(content).not.toContain('10.0.0.99');
    // Should detect MAC from cloud-init ci-info
    expect(content).toContain('00:0d:3a:ab:cd:ef');
    // Should show cloud-init source warning with file provenance
    expect(content).toMatch(/cloud-init/);
    expect(content).toContain('last reported configuration');
    expect(content).toMatch(/messages:\d+/);  // source file:lineNumber
  });

  test('detects SUSE network interface from InspectIaaSDisk cluster ZIP', async ({ page }) => {
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

    // Should detect eth0 from SUSE ifcfg path
    expect(content).toContain('eth0');
    // Should detect DHCP
    expect(content).toMatch(/dhcp/i);
    // Should detect DHCP IP from cloud-init-output.log
    expect(content).toContain('10.0.1.10');
    // Should detect MAC from cloud-init
    expect(content).toContain('60:45:bd:12:34:56');
    // Should show cloud-init source warning with file provenance
    expect(content).toMatch(/cloud-init/);
    expect(content).toContain('last reported configuration');
    expect(content).toMatch(/cloud-init-output\.log:\d+/);  // source file:lineNumber
  });
});
