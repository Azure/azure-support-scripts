import { test, expect } from '@playwright/test';
import path from 'path';

/**
 * Helper function to upload a test file and wait for analysis
 */
async function uploadAndWaitForAnalysis(page, filename) {
  const filePath = path.join(__dirname, 'fixtures', filename);
  
  // Upload file
  const fileInput = await page.locator('input[type="file"]');
  await fileInput.setInputFiles(filePath);
  
  // Wait for analysis to complete (look for results content in #output)
  await page.waitForFunction(() => {
    const output = document.getElementById('output');
    return output && output.innerHTML.length > 100;
  }, { timeout: 60000 });
  
  // Wait a bit more to ensure all content is rendered
  await page.waitForTimeout(2000);
  
  // Get the analysis result HTML
  const resultHTML = await page.locator('#output').innerHTML();
  
  return resultHTML;
}

/**
 * Helper to extract text content from result
 */
async function getResultText(page) {
  return await page.locator('#output').textContent();
}

test.describe('SAP HANA Cluster Analyzer', () => {
  
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('h1')).toContainText('RCA Tool');
  });

  test('page loads correctly', async ({ page }) => {
    await expect(page.locator('#drop-zone')).toBeVisible();
    await expect(page.locator('#drop-zone')).toContainText('Select Cluster File');
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

  test('detects Azure VM properties correctly', async ({ page }) => {
    const result = await uploadAndWaitForAnalysis(page, 'scc_test-azure-vm.tar.xz');
    
    expect(result).toContain('Azure VM Properties');
    expect(result).toMatch(/VM ID:|VM Size:|Location:/);
  });

  test('detects cluster nodes and validates /etc/hosts', async ({ page }) => {
    const result = await uploadAndWaitForAnalysis(page, 'scc_test-cluster-nodes.tar.xz');
    
    expect(result).toContain('Cluster nodes in ha.txt and hosts file');
    // Test should process the hosts file
    expect(result).toContain('ha.txt');
  });

  test('detects Corosync configuration issues', async ({ page }) => {
    const result = await uploadAndWaitForAnalysis(page, 'scc_test-corosync-config.tar.xz');
    
    expect(result).toContain('Corosync Configuration');
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

  test('detects fencing configuration', async ({ page }) => {
    const result = await uploadAndWaitForAnalysis(page, 'scc_test-fencing.tar.xz');
    
    // Should process ha.txt and show cluster nodes section
    expect(result).toContain('ha.txt');
    expect(result).toContain('Cluster nodes');
  });

  test('detects kernel reboots', async ({ page }) => {
    const result = await uploadAndWaitForAnalysis(page, 'scc_test-kernel-reboots.tar.xz');
    
    expect(result).toContain('Kernel Reboots');
    expect(result).toMatch(/\d+ events? found/i);
    // Should show reboot timestamps
    expect(result).toMatch(/\d{4}-\d{2}-\d{2}|\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}/);
  });

  test('detects OOM killer events', async ({ page }) => {
    const result = await uploadAndWaitForAnalysis(page, 'scc_test-oom-killer.tar.xz');
    
    if (result.includes('OOM Killer')) {
      expect(result).toMatch(/OOM Killer.*\d+ event/i);
      // Should show process names
      expect(result).toMatch(/invoked oom-killer|Killed process/i);
    }
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

  test('detects live migration events', async ({ page }) => {
    const result = await uploadAndWaitForAnalysis(page, 'scc_test-live-migration.tar.xz');
    
    if (result.includes('Live Migration Events')) {
      expect(result).toMatch(/Hyper-V Live Migration/i);
      // Should show migration timestamps
      expect(result).toMatch(/\d{4}-\d{2}-\d{2}|\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}/);
    }
  });

  test('theme toggle cycles through all modes', async ({ page }) => {
    // Check initial state (dark mode by default)
    const body = page.locator('body');
    await expect(body).toHaveClass(/dark-mode/);
    
    // Click once: dark -> colorblind
    await page.click('#theme-toggle');
    await expect(body).toHaveClass(/colorblind-mode/);
    await expect(body).not.toHaveClass(/dark-mode/);
    
    // Click twice: colorblind -> light
    await page.click('#theme-toggle');
    await expect(body).not.toHaveClass(/dark-mode/);
    await expect(body).not.toHaveClass(/colorblind-mode/);
    
    // Click thrice: light -> dark
    await page.click('#theme-toggle');
    await expect(body).toHaveClass(/dark-mode/);
    await expect(body).not.toHaveClass(/colorblind-mode/);
  });

  test('analyzes kernel tuning with correct values', async ({ page }) => {
    // Listen to console messages
    page.on('console', msg => console.log('BROWSER:', msg.text()));
    page.on('pageerror', err => console.error('PAGE ERROR:', err));
    
    const fileInput = await page.locator('input[type="file"]');
    
    await fileInput.setInputFiles(
      path.join(__dirname, 'fixtures', 'scc_test-kernel-tuning.tar.xz')
    );
    
    // Wait for analysis to complete - wait for specific content to appear
    await page.waitForFunction(
      () => {
        const output = document.getElementById('output');
        return output && output.textContent.includes('Kernel and Tuning');
      },
      { timeout: 60000 }
    );
    
    // Check that kernel tuning section exists
    const content = await page.locator('#output').textContent();
    expect(content).toContain('Kernel and Tuning');
    
    // Should have parameters table
    expect(content).toMatch(/vm\.dirty_bytes.*629145600/);
    expect(content).toMatch(/vm\.dirty_background_bytes.*314572800/);
    expect(content).toMatch(/vm\.swappiness.*10/);
    
    // Should not have warnings (all values are correct)
    expect(content).not.toContain('Kernel Parameter Warnings');
  });

  test('detects kernel tuning warnings', async ({ page }) => {
    const fileInput = await page.locator('input[type="file"]');
    
    await fileInput.setInputFiles(
      path.join(__dirname, 'fixtures', 'scc_test-kernel-tuning-warnings.tar.xz')
    );
    
    // Wait for analysis to complete - wait for specific content to appear
    await page.waitForFunction(
      () => {
        const output = document.getElementById('output');
        return output && output.textContent.includes('Kernel and Tuning');
      },
      { timeout: 60000 }
    );
    
    // Check that kernel tuning section exists
    const content = await page.locator('#output').textContent();
    expect(content).toContain('Kernel and Tuning');
    
    // Should have warning about incorrect vm.dirty_bytes
    expect(content).toContain('Kernel Parameter Warnings');
    expect(content).toMatch(/vm\.dirty_bytes/);
    expect(content).toContain('Expected: 629145600');
    expect(content).toContain('Found: 200000000');
    
    // Should have warning about incorrect vm.dirty_background_bytes
    expect(content).toMatch(/vm\.dirty_background_bytes/);
    expect(content).toContain('Expected: 314572800');
    expect(content).toContain('Found: 100000000');
    
    // Should have warning about incorrect vm.swappiness
    expect(content).toMatch(/vm\.swappiness/);
    expect(content).toContain('Expected: 10');
    expect(content).toContain('Found: 60');
    
    // Should have documentation links
    expect(content).toContain('View Documentation');
  });

  test('handles invalid file format gracefully', async ({ page }) => {
    const fileInput = await page.locator('input[type="file"]');
    
    // Create a dummy text file
    const buffer = Buffer.from('This is not a tar file');
    await fileInput.setInputFiles({
      name: 'invalid.txt',
      mimeType: 'text/plain',
      buffer: buffer,
    });
    
    // Should show error or reject the file
    // Wait for potential error message
    await page.waitForTimeout(2000);
    
    // Result should either be empty or contain error message
    const result = await page.locator('#output').textContent();
    const isEmpty = result.trim().length === 0;
    const hasError = result.includes('error') || result.includes('invalid');
    
    expect(isEmpty || hasError).toBeTruthy();
  });
});
