import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : 4,
  reporter: [
    ['html', { outputFolder: 'playwright-report-leptos', open: 'never' }],
    ['junit', { outputFile: 'playwright-report-leptos/junit.xml' }],
    ['list'],
    ['monocart-reporter', {
      name: 'RCA Tool Leptos Coverage Report',
      outputFile: './coverage-report-leptos/index.html',
      coverage: {
        reports: [
          ['v8', { outputFile: 'coverage-report-leptos/v8/index.html' }],
          ['console-details'],
        ],
        entryFilter: (entry) => {
          if (entry.url.includes('/web-leptos/dist/')
              && !entry.url.includes('node_modules')) {
            return true;
          }
          if (entry.url.startsWith('file://') && entry.url.includes('/src/')) {
            return true;
          }
          return false;
        },
        sourceFilter: (sourcePath) => {
          return !sourcePath.includes('node_modules')
            && !sourcePath.includes('docs/');
        },
      }
    }]
  ],
  use: {
    baseURL: process.env.BASE_URL || 'http://localhost:8080',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },

  projects: [
    {
      name: 'local-leptos',
      use: {
        ...devices['Desktop Chrome'],
      },
    },
    {
      name: 'deployed-leptos',
      use: {
        ...devices['Desktop Chrome'],
        baseURL: (process.env.DEPLOYED_URL || 'https://fede2cr.github.io/azure-support-scripts').replace(/\/?$/, '/'),
      },
    },
  ],

  webServer: (process.env.BASE_URL || process.env.DEPLOYED_URL) ? undefined : {
    command: 'npx http-server ../ -p 8080',
    port: 8080,
    reuseExistingServer: !process.env.CI,
  },
});
