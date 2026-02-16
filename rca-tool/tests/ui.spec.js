/**
 * @module tests/ui
 * @description Playwright tests for general UI behaviour and error handling.
 *
 * Verifies page loading, dark/colorblind/light theme cycling,
 * graceful handling of invalid file uploads, and resilience against
 * corrupted or truncated `tar.xz` archives.
 */
import { test, expect } from '@playwright/test';
import { uploadAndWaitForAnalysis, navigateToApp, fixturePath } from './test-helpers.js';

test.describe('UI and Error Handling', () => {

  test.beforeEach(async ({ page }, testInfo) => {
    await navigateToApp(page, testInfo);
    await expect(page.locator('h1')).toContainText('RCA Tool');
  });

  test('page loads correctly', async ({ page }) => {
    await expect(page.locator('#drop-zone')).toBeVisible();
    await expect(page.locator('#drop-zone')).toContainText('Drag and Drop Support File');
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

  test('handles corrupted/truncated tar.xz file gracefully', async ({ page }) => {
    // Capture console logs to verify error handling
    const logs = [];
    page.on('console', msg => logs.push(msg.text()));
    
    const fileInput = await page.locator('input[type="file"]');
    
    // Use corrupted fixture
    await fileInput.setInputFiles(fixturePath('scc_test-corrupted.tar.xz'));
    
    // Wait for processing attempt
    await page.waitForTimeout(5000);
    
    // Check that page didn't crash and shows some content
    const content = await page.locator('#output').textContent();
    
    // Should not be completely empty
    expect(content.length).toBeGreaterThan(0);
    
    // Should indicate corruption or error
    const hasCorruptionIndicator = 
      content.toLowerCase().includes('corrupt') ||
      content.toLowerCase().includes('error') ||
      content.toLowerCase().includes('fail') ||
      content.toLowerCase().includes('incomplete');
    
    expect(hasCorruptionIndicator).toBeTruthy();
    
    // Should show some progress (blocks/bytes processed)
    const contentLower = content.toLowerCase();
    const showsProgress = 
      contentLower.includes('block') ||
      contentLower.includes('byte') ||
      contentLower.includes('decompressed');
    
    expect(showsProgress).toBeTruthy();
  });
});
