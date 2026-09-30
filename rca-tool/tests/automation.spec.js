/**
 * @module tests/automation
 * @description Playwright tests for {@link module:parsers/automation}.
 *
 * Verifies detection of Ansible executions including command patterns,
 * execution counts, and `yum install` invocations from SCC archives.
 */
import { test, expect } from './coverage-fixture.js';
import { uploadAndWaitForAnalysis, navigateToApp } from './test-helpers.js';

test.describe('Automation Parser', () => {

  test.beforeEach(async ({ page }, testInfo) => {
    await navigateToApp(page, testInfo);
    await expect(page.locator('h1')).toContainText('RCA Tool');
  });

  test('detects automation tool usage (Ansible)', async ({ page }) => {
    // Listen to console messages
    page.on('console', msg => console.log('BROWSER:', msg.text()));
    page.on('pageerror', err => console.error('PAGE ERROR:', err));
    
    const result = await uploadAndWaitForAnalysis(page, 'scc_test-automation.tar.xz');
    
    // Should detect automation tools
    expect(result).toContain('Automation Tools Usage');
    
    // Should show Ansible executions
    expect(result).toContain('Ansible');
    expect(result).toMatch(/5 execution/i);
    
    // Should show ansible commands
    expect(result).toContain('yum install -y httpd');
    expect(result).toContain('Invoked with name=httpd');
    
    // Should show detection pattern
    expect(result).toContain('ansible-command:');
  });
});
