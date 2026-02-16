/**
 * @module tests/docs
 * @description Playwright tests for the generated JSDoc API documentation.
 *
 * Confirms that the docs index page lists every expected module and
 * that representative module pages render with the correct content
 * (e.g. `parsers/automation` → Ansible, `parsers/cluster` →
 * Pacemaker/Corosync/STONITH).
 */
import { test, expect } from './coverage-fixture.js';

test.describe('API Documentation', () => {

  const expectedModules = [
    'parsers/automation',
    'parsers/azure',
    'parsers/cluster',
    'parsers/events',
    'parsers/network-interfaces',
    'parsers/networking',
    'parsers/packages',
    'parsers/services',
    'parsers/storage',
    'parsers/unix',
    'parsers/vmcore',
    'tests/automation',
    'tests/azure',
    'tests/cluster',
    'tests/docs',
    'tests/events',
    'tests/network-interfaces',
    'tests/networking',
    'tests/packages',
    'tests/services',
    'tests/storage',
    'tests/sysinfo-parser',
    'tests/test-helpers',
    'tests/ui',
    'tests/unix',
    'tests/vmcore',
    'utils',
    'worker',
  ];

  test('docs index page loads and lists all modules', async ({ page }, testInfo) => {
    const docsPath = testInfo.project.name === 'deployed' ? './docs/' : '/web/dist/docs/';
    await page.goto(docsPath);

    // The JSDoc index page should render with the correct title
    await expect(page).toHaveTitle(/JSDoc/);

    // Every module should appear as a link on the index page
    for (const mod of expectedModules) {
      await expect(page.locator(`a:has-text("${mod}")`)).toBeVisible();
    }
  });

  test('each module page loads and contains documentation', async ({ page }, testInfo) => {
    const docsBase = testInfo.project.name === 'deployed' ? './docs/' : '/web/dist/docs/';

    // Spot-check a few representative module pages for real content
    const checks = [
      {
        file: 'module-parsers_automation.html',
        contents: ['parsers/automation', 'Ansible', 'Puppet', 'Chef'],
      },
      {
        file: 'module-parsers_cluster.html',
        contents: ['parsers/cluster', 'Pacemaker', 'Corosync', 'STONITH'],
      },
      {
        file: 'module-parsers_storage.html',
        contents: ['parsers/storage', 'lvmConfigParser', 'fstabAnalysisParser'],
      },
      {
        file: 'module-parsers_unix.html',
        contents: ['parsers/unix', 'Time Synchronisation', 'RHUI'],
      },
      {
        file: 'module-utils.html',
        contents: ['utils'],
      },
    ];

    for (const check of checks) {
      await page.goto(docsBase + check.file);
      await expect(page).toHaveTitle(/JSDoc/);

      const body = await page.locator('body').textContent();
      for (const text of check.contents) {
        expect(body).toContain(text);
      }
    }
  });
});
