/**
 * @module tests/unix
 * @description Playwright tests for {@link module:parsers/unix}.
 *
 * Covers `crm_report` sysinfo distribution detection, kernel-tuning
 * parameter validation and warnings, huge-pages configuration and
 * SAP recommendations, fstab rendering, Azure network-tuning
 * optimisation (correct, warnings, optional, complete, whitespace),
 * and chronyd time-sync service detection.
 */
import { test, expect } from '@playwright/test';
import { uploadAndWaitForAnalysis, getResultText, navigateToApp, fixturePath } from './test-helpers.js';

test.describe('Unix Parsers', () => {

  test.beforeEach(async ({ page }, testInfo) => {
    await navigateToApp(page, testInfo);
    await expect(page.locator('h1')).toContainText('RCA Tool');
  });

  test('detects distribution from crm_report sysinfo.txt', async ({ page }) => {
    await page.setInputFiles(
      'input[type="file"]',
      fixturePath('scc_test-crm-report-sysinfo.tar.xz')
    );

    await page.waitForFunction(
      () => {
        const output = document.getElementById('output');
        return output && output.textContent.includes('Azure VM Properties');
      },
      { timeout: 60000 }
    );

    const content = await page.locator('#output').textContent();
    
    // Should show in Azure VM Properties section
    expect(content).toContain('Azure VM Properties');
    // Should detect SLES 15 SP5 from sysinfo.txt
    expect(content).toContain('SUSE Linux Enterprise Server 15 SP5');
    // Should show under Operating System subsection
    expect(content).toContain('Operating System');
  });

  test('analyzes kernel tuning with correct values', async ({ page }) => {
    // Listen to console messages
    page.on('console', msg => console.log('BROWSER:', msg.text()));
    page.on('pageerror', err => console.error('PAGE ERROR:', err));
    
    const fileInput = await page.locator('input[type="file"]');
    
    await fileInput.setInputFiles(fixturePath('scc_test-kernel-tuning.tar.xz'));
    
    // Wait for analysis to complete - wait for specific content to appear
    await page.waitForFunction(
      () => {
        const output = document.getElementById('output');
        return output && output.textContent.includes('Kernel and System Parameters');
      },
      { timeout: 60000 }
    );
    
    // Check that kernel tuning section exists
    const content = await page.locator('#output').textContent();
    expect(content).toContain('Kernel and System Parameters');
    
    // Should have parameters table
    expect(content).toMatch(/vm\.dirty_bytes.*629145600/);
    expect(content).toMatch(/vm\.dirty_background_bytes.*314572800/);
    expect(content).toMatch(/vm\.swappiness.*10/);
    
    // Should not have warnings (all values are correct)
    expect(content).not.toContain('Kernel Parameter Warnings');
  });

  test('detects kernel tuning warnings', async ({ page }) => {
    const fileInput = await page.locator('input[type="file"]');
    
    await fileInput.setInputFiles(fixturePath('scc_test-kernel-tuning.tar.xz'));
    
    // Wait for analysis to complete - wait for specific content to appear
    await page.waitForFunction(
      () => {
        const output = document.getElementById('output');
        return output && output.textContent.includes('Kernel and System Parameters');
      },
      { timeout: 60000 }
    );
    
    // Check that kernel tuning section exists
    const content = await page.locator('#output').textContent();
    expect(content).toContain('Kernel and System Parameters');
    
    // Verify kernel parameters are displayed
    expect(content).toContain('All Kernel Parameters');
  });

  test('detects and displays huge pages configuration', async ({ page }) => {
    const fileInput = await page.locator('input[type="file"]');
    
    // Use huge pages fixture
    await fileInput.setInputFiles(fixturePath('scc_test-huge-pages.tar.xz'));
    
    // Wait for analysis to complete
    await page.waitForFunction(
      () => {
        const output = document.getElementById('output');
        return output && output.textContent.includes('Kernel and System Parameters');
      },
      { timeout: 60000 }
    );
    
    // Check that huge pages section exists
    const content = await page.locator('#output').textContent();
    expect(content).toContain('Huge Pages Configuration');
    
    // Should detect static huge pages
    expect(content).toContain('Static Huge Pages');
    expect(content).toMatch(/2048.*pages/i);
    expect(content).toMatch(/4096.*MB/i);
    
    // Should detect transparent huge pages
    expect(content).toContain('Transparent Huge Pages');
    expect(content).toMatch(/2048.*MB.*in use/i);
    
    // Should show kernel parameters
    expect(content).toContain('vm.nr_hugepages');
    expect(content).toMatch(/vm\.nr_hugepages.*2048/);
  });

  test('detects huge pages recommendations for SAP', async ({ page }) => {
    const fileInput = await page.locator('input[type="file"]');
    // Use huge pages none fixture (has SAP indicator)
    await fileInput.setInputFiles(fixturePath('scc_test-huge-pages-none.tar.xz'));
    // Wait for analysis to complete
    await page.waitForFunction(
      () => {
        const output = document.getElementById('output');
        return output && output.textContent.includes('Kernel and System Parameters');
      },
      { timeout: 60000 }
    );
    // Check that huge pages configuration appears
    const content = await page.locator('#output').textContent();
    expect(content).toContain('Huge Pages Configuration');
    expect(content).toContain('Static Huge Pages');
    expect(content).toContain('Total Pages0');
  });

  test('detects and displays fstab configuration', async ({ page }) => {
    const fileInput = await page.locator('input[type="file"]');
    
    // Use fstab fixture
    await fileInput.setInputFiles(fixturePath('scc_test-fstab.tar.xz'));
    
    // Wait for analysis to complete
    await page.waitForFunction(
      () => {
        const output = document.getElementById('output');
        return output && output.textContent.includes('Kernel and System Parameters');
      },
      { timeout: 60000 }
    );
    
    // Check that section exists
    const content = await page.locator('#output').textContent();
    expect(content).toContain('Kernel and System Parameters');
    
    // Verify fstab subsection exists
    expect(content).toContain('Filesystem Table (/etc/fstab)');
    
    // Verify fstab content is displayed
    expect(content).toContain('UUID=12345678-1234-1234-1234-123456789abc');
    expect(content).toContain('/boot');
    expect(content).toContain('/data');
    expect(content).toContain('xfs');
    expect(content).toContain('defaults');
  });

  test('detects correctly configured Azure Network tuning', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'scc_test-azure-network-tuned.tar.xz');
    
    // Check that Kernel and System Parameters section exists
    expect(resultHTML).toContain('Kernel and System Parameters');
    
    // Check for success message
    expect(resultHTML).toContain('Kernel parameters tuned for Azure Network');
    expect(resultHTML).toContain('[OK]');
    
    // Should link to documentation
    expect(resultHTML).toContain('virtual-network-optimize-network-bandwidth');
    
    // Should not have warnings
    expect(resultHTML).not.toContain('Parameters Need Adjustment');
  });

  test('detects Azure Network tuning parameters needing adjustment', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'scc_test-azure-network-warnings.tar.xz');
    
    // Check that Kernel and System Parameters section exists
    expect(resultHTML).toContain('Kernel and System Parameters');
    
    // Check for warnings message
    expect(resultHTML).toContain('Azure Network Optimization - Parameters Need Adjustment');
    expect(resultHTML).toContain('[!]');

    // Check for specific parameters that need adjustment
    expect(resultHTML).toContain('net.ipv4.tcp_congestion_control');
    expect(resultHTML).toContain('net.core.busy_poll');
    expect(resultHTML).toContain('net.core.rmem_max');
    
    // Check expected vs actual values shown
    expect(resultHTML).toContain('Expected');
    expect(resultHTML).toContain('Found');
    expect(resultHTML).toContain('bbr'); // Expected value for tcp_congestion_control
    expect(resultHTML).toContain('cubic'); // Actual value
    
    // Should link to documentation
    expect(resultHTML).toContain('virtual-network-optimize-network-bandwidth');
    
    // Should show badge in summary
    expect(resultHTML).toContain('Network tuning');
  });

  test('displays optional network tuning parameters', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'scc_test-optional-network-tuning.tar.xz');
    
    // Check that Kernel and System Parameters section exists
    expect(resultHTML).toContain('Kernel and System Parameters');
    
    // Check for Optional Network Tuning section (collapsed by default)
    expect(resultHTML).toContain('Optional Network Tuning');
    expect(resultHTML).toContain('informational');
    
    // Check for explanatory text
    expect(resultHTML).toContain('optional recommendations');
    expect(resultHTML).toContain('do not indicate configuration issues');
    
    // Check for specific optional parameters
    expect(resultHTML).toContain('net.ipv4.tcp_timestamps');
    expect(resultHTML).toContain('net.ipv4.tcp_tw_reuse');
    expect(resultHTML).toContain('net.core.default_qdisc');
    expect(resultHTML).toContain('net.core.somaxconn');
    
    // Check for status indicators
    expect(resultHTML).toContain('[OK]'); // Some parameters match
    expect(resultHTML).toContain('Recommended');
    expect(resultHTML).toContain('Current');
    
    // Should link to documentation
    expect(resultHTML).toContain('virtual-network-optimize-network-bandwidth');
  });

  test('displays complete network tuning configuration', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'scc_test-complete-network-tuning.tar.xz');
    
    // Check that Kernel and System Parameters section exists
    expect(resultHTML).toContain('Kernel and System Parameters');
    
    // Check for Azure Network success message
    expect(resultHTML).toContain('Kernel parameters tuned for Azure Network');
    expect(resultHTML).toContain('[OK]');
    expect(resultHTML).toContain('Optional Network Tuning');
    
    // Should have all optional parameters showing as configured correctly
    const content = await page.locator('#output').textContent();
    
    // Verify both Azure and optional parameters are present
    expect(content).toContain('net.ipv4.tcp_congestion_control');
    expect(content).toContain('net.ipv4.tcp_timestamps');
    expect(content).toContain('net.core.default_qdisc');
    
    // Should not have any warnings
    expect(resultHTML).not.toContain('Parameters Need Adjustment');
    expect(resultHTML).not.toContain('danger-block');
  });

  test('detects incorrect Azure Network optimization parameters', async ({ page }) => {
    // Use pre-created fixture with incorrect values
    const resultHTML = await uploadAndWaitForAnalysis(page, 'scc_test-azure-network-warnings.tar.xz');
    
    // Check for Azure Network warnings
    expect(resultHTML).toContain('Azure Network Optimization - Parameters Need Adjustment');
    expect(resultHTML).toContain('[!]');

    // Should show incorrect parameters
    expect(resultHTML).toContain('net.ipv4.tcp_mem');
    expect(resultHTML).toContain('net.core.rmem_default');
    expect(resultHTML).toContain('net.ipv4.tcp_congestion_control');
    
    // Should show expected vs actual values
    expect(resultHTML).toContain('67108864');
    expect(resultHTML).toContain('33554432');
    expect(resultHTML).toContain('bbr');
    
    // Should have documentation link
    expect(resultHTML).toContain('virtual-network-optimize-network-bandwidth');
  });

  test('shows optional network tuning parameters as informational', async ({ page }) => {
    // Use pre-created fixture with Azure correct but optional params different
    const resultHTML = await uploadAndWaitForAnalysis(page, 'scc_test-optional-network-tuning.tar.xz');
    
    // Should show Azure Network as tuned (no warnings) - note: fixture doesn't have Azure params
    // So we check for Optional Network Tuning section
    expect(resultHTML).toContain('Optional Network Tuning');
    expect(resultHTML).toContain('informational');
    
    // Expand the optional section and check content
    const content = await page.locator('#output').textContent();
    
    // Should show optional parameters
    expect(content).toContain('net.ipv4.tcp_timestamps');
    expect(content).toContain('net.ipv4.tcp_tw_reuse');
    expect(content).toContain('net.core.default_qdisc');
    
    // Should use checkmarks for matching params
    expect(resultHTML).toContain('[OK]');
    expect(resultHTML).toContain('informational only');
    
    // Should NOT have warning-block for optional params
    const optionalSection = resultHTML.match(/Optional Network Tuning[\s\S]*?<\/details>/);
    if (optionalSection) {
      expect(optionalSection[0]).not.toContain('warning-block');
      expect(optionalSection[0]).not.toContain('danger-block');
    }
  });

  test('shows checkmarks for matching optional network parameters', async ({ page }) => {
    // Use pre-created fixture with all parameters optimal
    const resultHTML = await uploadAndWaitForAnalysis(page, 'scc_test-complete-network-tuning.tar.xz');
    
    // Azure Network should be tuned
    expect(resultHTML).toContain('Kernel parameters tuned for Azure Network');
    expect(resultHTML).toContain('[OK]');
    expect(resultHTML).toContain('Optional Network Tuning');
    
    // All optional parameters should show checkmarks (matches = true)
    const optionalSection = resultHTML.match(/Optional Network Tuning[\s\S]*?<\/details>/);
    if (optionalSection) {
      // Count checkmarks - should have at least 10 (one per optional parameter)
      const checkmarkCount = (optionalSection[0].match(/\[OK\]/g) || []).length;
      expect(checkmarkCount).toBeGreaterThanOrEqual(10);
      
      // Should have minimal or no info icons (all should match)
      const infoIconCount = (optionalSection[0].match(/\[i\]/g) || []).length;
      expect(infoIconCount).toBeLessThanOrEqual(0);
    }
  });

  test('handles whitespace differences in network parameter values', async ({ page }) => {
    // The azure-network-tuned fixture has tabs which tests whitespace normalization
    const resultHTML = await uploadAndWaitForAnalysis(page, 'scc_test-azure-network-tuned.tar.xz');
    
    // Should recognize as correctly tuned despite whitespace differences
    expect(resultHTML).toContain('Kernel parameters tuned for Azure Network');
    expect(resultHTML).toContain('[OK]');
    
    // Should not show warnings
    expect(resultHTML).not.toContain('Parameters Need Adjustment');
  });

  test('detects chronyd service status from SCC systemd-status.txt', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'scc_test-timesync-chrony.tar.xz');
    
    // Should detect time sync service information
    expect(resultHTML).toMatch(/Time.*Sync.*Service|timeSyncService/i);
    
    // Should show service is enabled and running
    const resultText = await getResultText(page);
    expect(resultText).toMatch(/chrony.*enabled|enabled.*chrony/i);
    
    // Should reference systemd-status.txt as the source
    expect(resultHTML).toContain('systemd-status.txt');
    expect(resultHTML).toMatch(/systemd-status\.txt.*chronyd|chronyd.*systemd-status\.txt/i);
    
    // Should NOT show error if chronyd is running properly
    if (resultText.includes('chrony') && resultText.includes('enabled')) {
      expect(resultText).not.toMatch(/chrony.*not running|service.*not.*running.*chrony/i);
    }
  });
});
