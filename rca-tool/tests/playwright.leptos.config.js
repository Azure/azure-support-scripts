import { defineConfig, devices } from '@playwright/test';

const localTestPort = process.env.LEPTOS_TEST_PORT || '4180';
const localBaseUrl = process.env.BASE_URL || `http://localhost:${localTestPort}`;

export default defineConfig({
  testDir: './',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: 0,
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
          if (((entry.url.includes('/web-leptos/dist/')
              || entry.url.startsWith(`${localBaseUrl}/`))
              && !entry.url.includes('node_modules'))) {
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
    baseURL: localBaseUrl,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },

  projects: [
    {
      name: 'local-leptos',
      use: {
        ...devices['Desktop Edge'],
        channel: 'msedge',
      },
    },
    {
      name: 'deployed-leptos',
      use: {
        ...devices['Desktop Edge'],
        channel: 'msedge',
        baseURL: (process.env.DEPLOYED_URL || 'https://fede2cr.github.io/azure-support-scripts').replace(/\/?$/, '/'),
      },
    },
  ],

  webServer: (process.env.BASE_URL || process.env.DEPLOYED_URL) ? undefined : {
    command: `cd .. && npx http-server web-leptos/dist -p ${localTestPort} -c-1`,
    port: Number(localTestPort),
    reuseExistingServer: !process.env.CI,
  },
});
