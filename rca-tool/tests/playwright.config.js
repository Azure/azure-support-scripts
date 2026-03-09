import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : 4,
  reporter: [
    ['html', { outputFolder: 'test-results', open: 'never' }],
    ['junit', { outputFile: 'test-results/junit.xml' }],
    ['list'],
    ['monocart-reporter', {
      name: 'RCA Tool Coverage Report',
      outputFile: './coverage-report/index.html',
      coverage: {
        reports: [
          // V8 native report with per-byte detail
          ['v8', { outputFile: 'coverage-report/v8/index.html' }],
          // Console summary printed after each run
          ['console-details'],
        ],
        // Include app files served from /web/dist/ AND worker source files (file://)
        entryFilter: (entry) => {
          // Main-thread Vite bundle
          if (entry.url.includes('/web/dist/')
              && !entry.url.includes('/web/dist/docs/')
              && !entry.url.includes('node_modules')) {
            return true;
          }
          // Istanbul-converted worker/parser source files
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
      name: 'local',
      use: { 
        ...devices['Desktop Edge'],
        channel: 'msedge',
      },
    },
    {
      name: 'deployed',
      use: { 
        ...devices['Desktop Edge'],
        channel: 'msedge',
        // Ensure trailing slash so relative paths work correctly
        // Note: URL('path', 'base') treats 'base' as a file unless it ends with /
        baseURL: (process.env.DEPLOYED_URL || 'https://fede2cr.github.io/azure-support-scripts').replace(/\/?$/, '/'),
      },
    },
  ],

  webServer: process.env.BASE_URL ? undefined : {
    command: 'npx http-server ../ -p 8080',
    port: 8080,
    reuseExistingServer: !process.env.CI,
  },
});
