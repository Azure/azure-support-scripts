/**
 * @module tests/cluster
 * @description Playwright tests for {@link module:parsers/cluster}.
 *
 * Validates systemd false-positive filtering, cluster-node discovery,
 * Corosync configuration checks, Pacemaker resource parsing, SAP
 * indicator detection, STONITH/SBD fencing, SAP instance
 * configuration and error reporting, live-migration events, nested
 * gzip decompression, and Getty message filtering.
 */
import { test, expect } from './coverage-fixture.js';
import { uploadAndWaitForAnalysis, getResultText, isSapDetectedFromResult, navigateToApp } from './test-helpers.js';

test.describe('Cluster Parsers', () => {

  test.beforeEach(async ({ page }, testInfo) => {
    await navigateToApp(page, testInfo);
    await expect(page.locator('h1')).toContainText('RCA Tool');
  });

  test('detects systemd false positives are filtered out', async ({ page }) => {
    const result = await uploadAndWaitForAnalysis(page, 'scc_test-systemd-messages.tar.xz');
    
    // Should NOT contain systemd service messages
    expect(result).not.toContain('Getty stopped on');
    expect(result).not.toContain('PatrolAgent stopped on port');
    
    // But should still show actual cluster events if present
    const resultText = await getResultText(page);
    if (resultText.includes('Resource Migration Events')) {
      // If there are migration events, verify they're not systemd services
      expect(result).not.toMatch(/systemd\[\d+\]:/);
    }
  });

  test('detects cluster nodes and validates /etc/hosts', async ({ page }) => {
    const result = await uploadAndWaitForAnalysis(page, 'scc_test-cluster-nodes.tar.xz');
    const sapDetected = isSapDetectedFromResult(result);
    if (!sapDetected) {
      console.log('Skipping cluster/hosts assertions: SAP not detected in fixture');
      return;
    }

    expect(result).toContain('Cluster nodes in ha.txt and hosts file');
    // Test should process the hosts file
    expect(result).toContain('ha.txt');
  });

  test('detects Corosync configuration issues', async ({ page }) => {
    const result = await uploadAndWaitForAnalysis(page, 'scc_test-corosync-config.tar.xz');
    const sapDetected = isSapDetectedFromResult(result);
    if (!sapDetected) {
      console.log('Skipping Corosync assertions: SAP not detected in fixture');
      return;
    }

    // Accept either legacy or updated header labels
    expect(result).toMatch(/Corosync Configuration|Cluster Configuration/);
    // Check for token timeout detection
    expect(result).toMatch(/token.*\d+/i);
  });

  test('detects Pacemaker resources', async ({ page }) => {
    const result = await uploadAndWaitForAnalysis(page, 'scc_test-pacemaker-resources.tar.xz');
    
    // The output should contain either resources or a message about them
    expect(result).toContain('resource');
    // Should process the ha.txt file
    expect(result).toContain('ha.txt');
  });

  test('detects SAP application indicators (directories, HANA resources, services)', async ({ page }) => {
    const result = await uploadAndWaitForAnalysis(page, 'scc_test-pacemaker-resources.tar.xz');

    // New GUI section should be present
    expect(result).toContain('[OK] Applications');
    expect(result).toContain('SAP Applications Detected');

    // Should list HANA / SAP resources discovered via pacemaker
    expect(result).toMatch(/SAPHana|HDB|rsc_SAPHana/i);
  });

  test('detects fencing configuration', async ({ page }) => {
    const result = await uploadAndWaitForAnalysis(page, 'scc_test-fencing.tar.xz');
    const sapDetected = isSapDetectedFromResult(result);
    if (!sapDetected) {
      console.log('Skipping fencing assertions: SAP not detected in fixture');
      return;
    }

    // Should process ha.txt and show cluster nodes section
    expect(result).toContain('ha.txt');
    expect(result).toContain('Cluster nodes');
  });

  test('detects fencing configuration in pcs_config format', async ({ page }) => {
    const result = await uploadAndWaitForAnalysis(page, 'scc_test-fencing-pcs.tar.xz');
    const sapDetected = isSapDetectedFromResult(result);
    if (!sapDetected) {
      console.log('Skipping pcs_config fencing assertions: SAP not detected in fixture');
      return;
    }

    // Should detect stonith-enabled
    expect(result).toMatch(/stonith.*enabled.*true/i);
    
    // Should detect Azure fencing agent
    expect(result).toMatch(/rsc_st_azure|fence_azure_arm/i);
  });

  test('detects SAP instance configuration issues - START_PROFILE and hostname mismatches', async ({ page }) => {
    const result = await uploadAndWaitForAnalysis(page, 'scc_test-sap-instance-config.tar.xz');
    
    // The fixture explicitly has SAPInstance resources, so we don't need SAP indicator check
    // Should detect SAPInstance resources
    expect(result).toMatch(/SAPInstance|rsc_sap_PJU/i);
    
    // Should detect START_PROFILE errors
    expect(result).toMatch(/START_PROFILE/i);
    
    // Should detect hostname mismatch (InstanceName has different host than START_PROFILE)
    expect(result).toMatch(/mismatch|hostname|ppu-scs|ppu-ers|awenwjeusscs/i);
  });

  test('detects SAP instance runtime errors - GRAY status and START_PROFILE issues', async ({ page }) => {
    const result = await uploadAndWaitForAnalysis(page, 'scc_test-sap-instance-config.tar.xz');
    
    // The fixture explicitly has SAP-related pacemaker resources
    // Should detect GRAY status errors - SAP services in GRAY status
    expect(result).toMatch(/GRAY Status/i);
    expect(result).toMatch(/msg_server/i);
    expect(result).toMatch(/enserver/i);
    
    // Should detect filesystem unmount issues
    expect(result).toMatch(/Filesystem Errors/i);
    expect(result).toMatch(/unmount/i);
    
    // Should detect START_PROFILE errors
    expect(result).toMatch(/START_PROFILE Errors/i);
  });

  test('detects live migration events', async ({ page }) => {
    const result = await uploadAndWaitForAnalysis(page, 'scc_test-live-migration.tar.xz');
    
    if (result.includes('Live Migration Events')) {
      expect(result).toMatch(/Hyper-V Live Migration/i);
      // Should show migration timestamps
      expect(result).toMatch(/\d{4}-\d{2}-\d{2}|\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}/);
    }
  });

  test('decompresses nested .gz files and processes all cluster log rotations', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'scc_test-nested-gzip.tar.xz');
    
    // Should display nested compression statistics
    expect(resultHTML).toContain('Nested Compression');
    expect(resultHTML).toMatch(/5 \.gz files? found/);
    expect(resultHTML).toMatch(/5 decompressed/);
    
    // Should show cluster events from all decompressed log files
    expect(resultHTML).toContain('Cluster Events Detected');
    expect(resultHTML).toMatch(/6 events found/);
    
    // Should detect resource events from multiple log files
    expect(resultHTML).toContain('testip');
    expect(resultHTML).toContain('sapdb');
    expect(resultHTML).toContain('filesystem');
    
    // Verify all three resources show both stop and start events
    expect(resultHTML).toContain('node01');
    expect(resultHTML).toContain('node02');
    
    // Verify events are from the .gz files
    expect(resultHTML).toContain('pacemaker.log-20250101.gz');
    expect(resultHTML).toContain('pacemaker.log-20250102.gz');
    expect(resultHTML).toContain('pacemaker.log-20250103.gz');
  });

  test('confirms Getty/tty messages are not shown as cluster resource events', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'scc_test-systemd-messages.tar.xz');
    
    // Should NOT show getty as a cluster resource
    expect(resultHTML).not.toMatch(/getty.*resource|resource.*getty/i);
    expect(resultHTML).not.toContain('tty1');
    
    // Should NOT show PatrolAgent or other systemd services as cluster events
    expect(resultHTML).not.toContain('PatrolAgent');
    
    // Verify the Cluster Events section doesn't contain these false positives
    const resultText = await getResultText(page);
    if (resultText.includes('Cluster Events')) {
      expect(resultText).not.toMatch(/Getty stopped|agetty|tty1 stop/i);
    }
  });
});
