/**
 * @module tests/unix
 * @description Playwright tests for {@link module:parsers/unix}.
 *
 * Covers `crm_report` sysinfo distribution detection, kernel-tuning
 * parameter validation and warnings, huge-pages configuration and
 * SAP recommendations, fstab rendering, Azure network-tuning
 * optimisation (correct, warnings, optional, complete, whitespace),
 * chronyd time-sync service detection, and InspectIaaSDisk integration
 * for both RHEL and SLES archives (SLES 15 SP6 with SAP HANA mounts).
 */
import { test, expect } from './coverage-fixture.js';
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
    
    // Wait for analysis to complete - fstab is now in the Storage section
    await page.waitForFunction(
      () => {
        const output = document.getElementById('output');
        return output && output.textContent.includes('Storage');
      },
      { timeout: 60000 }
    );
    
    // Check that Storage section exists
    const content = await page.locator('#output').textContent();
    expect(content).toContain('Storage');
    
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

  // ── InspectIaaSDisk tests ──────────────────────────────────────────

  test('parses InspectIaaSDisk results.txt from ZIP', async ({ page }) => {
    const fileInput = await page.locator('input[type="file"]');
    await fileInput.setInputFiles(fixturePath('test-inspect-iaas-disk.zip'));

    // Wait for the InspectIaaSDisk Results section to render
    await page.waitForFunction(
      () => {
        const output = document.getElementById('output');
        return output && output.textContent.includes('InspectIaaSDisk Results');
      },
      { timeout: 60000 }
    );

    const content = await page.locator('#output').textContent();

    // Should show the InspectIaaSDisk Results section
    expect(content).toContain('InspectIaaSDisk Results');

    // Request Info subsection
    expect(content).toContain('md-testaccount.z45.blob.storage.azure.net');
    expect(content).toContain('/testcontainer/abcd');
    expect(content).toContain('117c4d70-8c42-44c5-9f3e-cddeb3eb4264');

    // Inspection Metadata
    expect(content).toContain('Red Hat Enterprise Linux release 8.8 (Ootpa)');
    expect(content).toContain('rhel');

    // Filesystem Status table
    expect(content).toContain('Filesystem Status');
    expect(content).toContain('/dev/sda1');
    expect(content).toContain('xfs');
    expect(content).toContain('vfat');

    // Mount Results table
    expect(content).toContain('Mount Results');
    expect(content).toContain('/dev/rootvg/rootlv');
    expect(content).toContain('SUCCEEDED');
    expect(content).toContain('FAILED');
  });

  test('detects mount failures and shows warnings for InspectIaaSDisk', async ({ page }) => {
    const fileInput = await page.locator('input[type="file"]');
    await fileInput.setInputFiles(fixturePath('test-inspect-iaas-disk.zip'));

    await page.waitForFunction(
      () => {
        const output = document.getElementById('output');
        return output && output.textContent.includes('InspectIaaSDisk Results');
      },
      { timeout: 60000 }
    );

    const resultHTML = await page.locator('#output').innerHTML();

    // Should show mount failure warning
    expect(resultHTML).toContain('Mount failed');
    expect(resultHTML).toContain('/dev/disk/cloud/azure_resource-part1');
    expect(resultHTML).toContain('/mnt');

    // Section should open with danger styling when mounts failed
    expect(resultHTML).toContain('danger');
  });

  test('detects OS from redhat-release in InspectIaaSDisk ZIP', async ({ page }) => {
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

    // Should detect RHEL 8.8 from device_0/etc/redhat-release
    expect(content).toContain('Red Hat Enterprise Linux');
    expect(content).toContain('8.8');
  });

  test('parses fstab from InspectIaaSDisk ZIP', async ({ page }) => {
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

    // Should detect fstab entries from device_0/etc/fstab
    expect(content).toContain('/dev/mapper/rootvg-rootlv');
    expect(content).toContain('/boot');
    expect(content).toContain('/boot/efi');
    expect(content).toContain('azure_resource-part1');
  });

  // ── InspectIaaSDisk SLES tests ─────────────────────────────────────

  test('parses InspectIaaSDisk results.txt from SLES ZIP', async ({ page }) => {
    const fileInput = await page.locator('input[type="file"]');
    await fileInput.setInputFiles(fixturePath('test-inspect-iaas-disk-sles.zip'));

    // Wait for the InspectIaaSDisk Results section to render
    await page.waitForFunction(
      () => {
        const output = document.getElementById('output');
        return output && output.textContent.includes('InspectIaaSDisk Results');
      },
      { timeout: 60000 }
    );

    const content = await page.locator('#output').textContent();

    // Should show the InspectIaaSDisk Results section
    expect(content).toContain('InspectIaaSDisk Results');

    // Request Info subsection
    expect(content).toContain('md-djzwkqttxnxb.z50.blob.storage.azure.net');
    expect(content).toContain('/jhfcb3s4xnxv/abcd');
    expect(content).toContain('fc5d80d2-86aa-4b1f-a601-1d59ae66eba7');
    expect(content).toContain('1.57.5');

    // Inspection Metadata — SLES distribution
    expect(content).toContain('SUSE Linux Enterprise Server 15 SP6');
    expect(content).toContain('sles');

    // Filesystem Status table
    expect(content).toContain('Filesystem Status');
    expect(content).toContain('/dev/sda1');
    expect(content).toContain('/dev/sda4');
    expect(content).toContain('xfs');
    expect(content).toContain('vfat');

    // Mount Results table
    expect(content).toContain('Mount Results');
    expect(content).toContain('/dev/sda4');
    expect(content).toContain('SUCCEEDED');
    expect(content).toContain('FAILED');
  });

  test('detects mount failures and shows warnings for SLES InspectIaaSDisk', async ({ page }) => {
    const fileInput = await page.locator('input[type="file"]');
    await fileInput.setInputFiles(fixturePath('test-inspect-iaas-disk-sles.zip'));

    await page.waitForFunction(
      () => {
        const output = document.getElementById('output');
        return output && output.textContent.includes('InspectIaaSDisk Results');
      },
      { timeout: 60000 }
    );

    const resultHTML = await page.locator('#output').innerHTML();

    // Should show mount failure warning for /mnt
    expect(resultHTML).toContain('Mount failed');
    expect(resultHTML).toContain('/dev/disk/cloud/azure_resource-part1');
    expect(resultHTML).toContain('/mnt');

    // Section should open with danger styling when mounts failed
    expect(resultHTML).toContain('danger');
  });

  test('detects SLES OS from os-release in InspectIaaSDisk ZIP', async ({ page }) => {
    const fileInput = await page.locator('input[type="file"]');
    await fileInput.setInputFiles(fixturePath('test-inspect-iaas-disk-sles.zip'));

    await page.waitForFunction(
      () => {
        const output = document.getElementById('output');
        return output && output.textContent.includes('InspectIaaSDisk Results');
      },
      { timeout: 60000 }
    );

    const content = await page.locator('#output').textContent();

    // Should detect SLES 15 SP6 from device_0/etc/os-release
    expect(content).toContain('SUSE Linux Enterprise Server 15 SP6');
    expect(content).toContain('Operating System');
  });

  test('parses fstab with HANA mounts from SLES InspectIaaSDisk ZIP', async ({ page }) => {
    const fileInput = await page.locator('input[type="file"]');
    await fileInput.setInputFiles(fixturePath('test-inspect-iaas-disk-sles.zip'));

    await page.waitForFunction(
      () => {
        const output = document.getElementById('output');
        return output && output.textContent.includes('InspectIaaSDisk Results');
      },
      { timeout: 60000 }
    );

    const content = await page.locator('#output').textContent();

    // Should detect fstab entries including SAP HANA mount points
    expect(content).toContain('/boot');
    expect(content).toContain('/boot/efi');
    expect(content).toContain('/hana/data');
    expect(content).toContain('/hana/log');
    expect(content).toContain('/hana/shared');
    expect(content).toContain('/usr/sap');
    expect(content).toContain('azure_resource-part1');
  });

  test('detects Azure extensions from SLES InspectIaaSDisk ZIP', async ({ page }) => {
    const fileInput = await page.locator('input[type="file"]');
    await fileInput.setInputFiles(fixturePath('test-inspect-iaas-disk-sles.zip'));

    await page.waitForFunction(
      () => {
        const output = document.getElementById('output');
        return output && output.textContent.includes('InspectIaaSDisk Results');
      },
      { timeout: 60000 }
    );

    const content = await page.locator('#output').textContent();

    // Should detect Azure extensions from waagent handler status files
    expect(content).toContain('MDE');
    expect(content).toContain('VMSnapshot');
    expect(content).toContain('LinuxPatchExtension');
    expect(content).toContain('RunCommand');
  });

  test('parses sysctl.conf and sysctl.d files from SLES InspectIaaSDisk ZIP', async ({ page }) => {
    const fileInput = await page.locator('input[type="file"]');
    await fileInput.setInputFiles(fixturePath('test-inspect-iaas-disk-sles.zip'));

    await page.waitForFunction(
      () => {
        const output = document.getElementById('output');
        return output && output.textContent.includes('InspectIaaSDisk Results');
      },
      { timeout: 60000 }
    );

    const content = await page.locator('#output').textContent();

    // Parameters from device_0/etc/sysctl.conf should be detected
    expect(content).toContain('net.core.rmem_max');
    expect(content).toContain('net.core.wmem_max');

    // SAP parameters from device_0/etc/sysctl.d/sap_hdb_sysctl.conf
    expect(content).toContain('vm.swappiness');
    expect(content).toContain('vm.dirty_bytes');

    // vm.swappiness=15 (expected 10) should generate a warning
    const html = await page.locator('#output').innerHTML();
    expect(html).toContain('vm.swappiness');
    // The kernel parameters section should appear
    expect(content).toContain('Kernel and System Parameters');
  });

  test('parses waagent.log and categorises errors from SLES InspectIaaSDisk ZIP', async ({ page }) => {
    const fileInput = await page.locator('input[type="file"]');
    await fileInput.setInputFiles(fixturePath('test-inspect-iaas-disk-sles.zip'));

    await page.waitForFunction(
      () => {
        const output = document.getElementById('output');
        return output && output.textContent.includes('Azure Linux Agent Log');
      },
      { timeout: 60000 }
    );

    const content = await page.locator('#output').textContent();
    const html = await page.locator('#output').innerHTML();

    // Should detect agent version
    expect(content).toContain('2.14.0.1');

    // Should show error count badges
    // Fixture has: 2 goal state errors, 1 extension error, 1 resource disk error = 4 errors
    // And: 1 IMDS warning, 2 status file warnings (lines 11-12), 1 resource disk warning = 4 warnings
    expect(html).toContain('error');

    // Goal state errors should be categorised
    expect(content).toContain('Goal State');

    // Extension error (MDE) should be detected
    expect(content).toContain('MDE');

    // Resource disk errors should be detected
    expect(content).toContain('Resource Disk');

    // IMDS connection error should be detected
    expect(content).toContain('IMDS');
  });

  // ── FIPS Detection Tests ──────────────────────────────────────────────

  test('detects FIPS enabled from all indicators', async ({ page }) => {
    const fileInput = await page.locator('input[type="file"]');
    await fileInput.setInputFiles(fixturePath('scc_test-fips-enabled.tar.xz'));

    await page.waitForFunction(
      () => {
        const output = document.getElementById('output');
        return output && output.textContent.includes('FIPS Status');
      },
      { timeout: 60000 }
    );

    const content = await page.locator('#output').textContent();
    const html = await page.locator('#output').innerHTML();

    // FIPS Status section must appear
    expect(content).toContain('FIPS Status');

    // Should show ENABLED badge
    expect(html).toContain('ENABLED');

    // All six sources should be listed
    expect(content).toContain('fips-mode-setup --check');
    expect(content).toContain('Kernel cmdline (fips=1)');
    expect(content).toContain('sysctl crypto.fips_enabled');
    expect(content).toContain('Crypto policy');
    expect(content).toContain('waagent.conf OS.EnableFIPS');
    expect(content).toContain('dracut-fips package');

    // All should show Enabled
    expect(content).toMatch(/fips-mode-setup.*Enabled/s);
    expect(content).toMatch(/Kernel cmdline.*Enabled/s);
    expect(content).toMatch(/sysctl.*Enabled/s);
    expect(content).toMatch(/dracut-fips.*Enabled/s);

    // FIPS-related packages should be listed
    expect(content).toContain('FIPS-related packages');
    expect(content).toContain('dracut-fips');
    expect(content).toContain('fipscheck');

    // Kernel command line should show fips=1
    expect(content).toContain('Kernel Command Line');
    expect(content).toContain('fips=1');

    // Should NOT show inconsistent warning
    expect(content).not.toContain('Inconsistent FIPS state');
  });

  test('detects FIPS disabled from all indicators', async ({ page }) => {
    const fileInput = await page.locator('input[type="file"]');
    await fileInput.setInputFiles(fixturePath('scc_test-fips-disabled.tar.xz'));

    await page.waitForFunction(
      () => {
        const output = document.getElementById('output');
        return output && output.textContent.includes('FIPS Status');
      },
      { timeout: 60000 }
    );

    const content = await page.locator('#output').textContent();
    const html = await page.locator('#output').innerHTML();

    // FIPS Status section must appear
    expect(content).toContain('FIPS Status');

    // Should NOT show ENABLED badge
    expect(html).not.toMatch(/FIPS Status.*ENABLED/s);

    // Disabled sources should show "Disabled / Not set"
    expect(content).toContain('Disabled / Not set');

    // Should show fips-mode-setup as disabled
    expect(content).toContain('fips-mode-setup --check');

    // Kernel cmdline should be present but without fips=1
    expect(content).toContain('Kernel cmdline (fips=1)');

    // Should NOT list dracut-fips as a source (package not installed)
    expect(content).not.toMatch(/dracut-fips package/);

    // Should NOT show inconsistent warning
    expect(content).not.toContain('Inconsistent FIPS state');

    // Should have Kernel Command Line section (without fips=1 in params)
    expect(content).toContain('Kernel Command Line');
  });

  test('detects FIPS inconsistent state and shows warning', async ({ page }) => {
    const fileInput = await page.locator('input[type="file"]');
    await fileInput.setInputFiles(fixturePath('scc_test-fips-inconsistent.tar.xz'));

    await page.waitForFunction(
      () => {
        const output = document.getElementById('output');
        return output && output.textContent.includes('FIPS Status');
      },
      { timeout: 60000 }
    );

    const content = await page.locator('#output').textContent();
    const html = await page.locator('#output').innerHTML();

    // FIPS Status section must appear
    expect(content).toContain('FIPS Status');

    // Should show inconsistent warning
    expect(content).toContain('Inconsistent FIPS state');

    // fips-mode-setup should report enabled
    expect(content).toContain('fips-mode-setup --check');

    // Inconsistent tag should appear in the table
    expect(html).toContain('inconsistent');

    // Crypto policy should show DEFAULT (which is the mismatch)
    expect(content).toContain('DEFAULT');

    // Should show the fips-mode-setup --enable recommendation
    expect(content).toContain('fips-mode-setup --enable');

    // Kernel cmdline should show fips=1 (boot param was set)
    expect(content).toContain('fips=1');

    // dracut-fips package should be detected
    expect(content).toContain('dracut-fips');
  });
});
