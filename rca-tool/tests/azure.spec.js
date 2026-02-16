/**
 * @module tests/azure
 * @description Playwright tests for {@link module:parsers/azure}.
 *
 * Covers Azure VM property detection, BYOS / PAYG billing-model
 * classification across SLES, RHEL, and Ubuntu images, SCC
 * `metadata.txt` format parsing, and Azure storage-type display
 * (Ultra Disk, Premium SSD v2).
 */
import { test, expect } from '@playwright/test';
import { uploadAndWaitForAnalysis, getResultText, navigateToApp, fixturePath } from './test-helpers.js';

test.describe('Azure Parser', () => {

  test.beforeEach(async ({ page }, testInfo) => {
    await navigateToApp(page, testInfo);
    await expect(page.locator('h1')).toContainText('RCA Tool');
  });

  test('detects Azure VM properties correctly', async ({ page }) => {
    const result = await uploadAndWaitForAnalysis(page, 'scc_test-azure-vm.tar.xz');
    
    expect(result).toContain('Azure VM Properties');
    expect(result).toMatch(/VM Size:|Publisher:|Offer:/);
  });

  test('detects BYOS billing model via license type (SLES)', async ({ page }) => {
    const fileInput = await page.locator('input[type="file"]');
    await fileInput.setInputFiles(fixturePath('scc_test-azure-vm.tar.xz'));

    await page.waitForFunction(
      () => {
        const output = document.getElementById('output');
        return output && output.textContent.includes('Azure VM Properties');
      },
      { timeout: 60000 }
    );

    const content = await page.locator('#output').textContent();
    
    // Should detect BYOS
    expect(content).toContain('BYOS');
    expect(content).toContain('License Type: SLES_BYOS');
  });

  test('detects PAYG billing model via license type (RHEL SAP HA)', async ({ page }) => {
    const fileInput = await page.locator('input[type="file"]');
    await fileInput.setInputFiles(fixturePath('scc_test-azure-vm-rhel-payg.tar.xz'));

    await page.waitForFunction(
      () => {
        const output = document.getElementById('output');
        return output && output.textContent.includes('Azure VM Properties');
      },
      { timeout: 60000 }
    );

    const content = await page.locator('#output').textContent();
    
    // Should detect PAYG
    expect(content).toContain('PAYG');
    expect(content).toContain('License Type: RHEL_SAPHA');
    expect(content).toMatch(/Billing Code:.*Linux_IaaS_Software_RedHat_SAP_HA/);
  });

  test('detects BYOS via billing code when license type is N/A (RHEL)', async ({ page }) => {
    const fileInput = await page.locator('input[type="file"]');
    await fileInput.setInputFiles(fixturePath('scc_test-azure-vm-rhel-byos.tar.xz'));

    await page.waitForFunction(
      () => {
        const output = document.getElementById('output');
        return output && output.textContent.includes('Azure VM Properties');
      },
      { timeout: 60000 }
    );

    const content = await page.locator('#output').textContent();
    
    // Should detect BYOS via billing code
    expect(content).toContain('BYOS');
    expect(content).toContain('Billing Code: Linux_IaaS');
  });

  test('detects PAYG via billing code when license type is NONE (SLES SAP)', async ({ page }) => {
    const fileInput = await page.locator('input[type="file"]');
    await fileInput.setInputFiles(fixturePath('scc_test-azure-vm-sles-payg.tar.xz'));

    await page.waitForFunction(
      () => {
        const output = document.getElementById('output');
        return output && output.textContent.includes('Azure VM Properties');
      },
      { timeout: 60000 }
    );

    const content = await page.locator('#output').textContent();
    
    // Should detect PAYG via billing code
    expect(content).toContain('PAYG');
    expect(content).toContain('Billing Code: Linux_IaaS_Software_SLES_for_SAP');
  });

  test('detects BYOS for Canonical Ubuntu via billing code', async ({ page }) => {
    const fileInput = await page.locator('input[type="file"]');
    await fileInput.setInputFiles(fixturePath('scc_test-azure-vm-ubuntu-byos.tar.xz'));

    await page.waitForFunction(
      () => {
        const output = document.getElementById('output');
        return output && output.textContent.includes('Azure VM Properties');
      },
      { timeout: 60000 }
    );

    const content = await page.locator('#output').textContent();
    
    // Should detect BYOS
    expect(content).toContain('BYOS');
    expect(content).toContain('Billing Code: Linux_IaaS_Canonical');
  });

  test('detects PAYG for Ubuntu Pro via license type', async ({ page }) => {
    const fileInput = await page.locator('input[type="file"]');
    await fileInput.setInputFiles(fixturePath('scc_test-azure-vm-ubuntu-pro.tar.xz'));

    await page.waitForFunction(
      () => {
        const output = document.getElementById('output');
        return output && output.textContent.includes('Azure VM Properties');
      },
      { timeout: 60000 }
    );

    const content = await page.locator('#output').textContent();
    
    // Should detect PAYG
    expect(content).toContain('PAYG');
    expect(content).toContain('License Type: UBUNTU_PRO');
  });

  test('detects Azure VM from SCC metadata.txt format', async ({ page }) => {
    await page.setInputFiles(
      'input[type="file"]',
      fixturePath('scc_test-azure-vm-scc-metadata.tar.xz')
    );

    await page.waitForFunction(
      () => {
        const output = document.getElementById('output');
        return output && output.textContent.includes('Azure VM Properties');
      },
      { timeout: 60000 }
    );

    const content = await page.locator('#output').textContent();
    
    // Should detect VM size from SCC metadata.txt
    expect(content).toContain('Standard_M64ds_v2');
    // Should detect PAYG
    expect(content).toContain('PAYG');
    // Should detect SLES SAP
    expect(content).toContain('SUSE');
  });

  test('detects and displays Azure storage types (Ultra Disk and Premium SSD v2)', async ({ page }) => {
    const resultHTML = await uploadAndWaitForAnalysis(page, 'scc_test-azure-vm-storage.tar.xz');
    
    // Should show storage section
    expect(resultHTML).toContain('Storage:');
    
    // Should show OS disk type
    expect(resultHTML).toContain('OS Disk:');
    expect(resultHTML).toContain('Premium SSD');
    
    // Should show data disks section
    expect(resultHTML).toContain('Data Disks:');
    expect(resultHTML).toContain('3 disk(s)');
    
    // Should detect Ultra Disk
    expect(resultHTML).toContain('Ultra Disk');
    expect(resultHTML).toContain('LUN 0');
    expect(resultHTML).toContain('512 GB');
    
    // Should detect Premium SSD v2
    expect(resultHTML).toContain('Premium SSD v2');
    expect(resultHTML).toContain('LUN 1');
    expect(resultHTML).toContain('256 GB');
    
    // Should show regular Premium SSD
    expect(resultHTML).toContain('LUN 2');
    expect(resultHTML).toContain('1024 GB');
  });
});
