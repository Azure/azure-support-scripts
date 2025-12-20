import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: [
    ['html', { outputFolder: 'test-results', open: 'never' }],
    ['junit', { outputFile: 'test-results/junit.xml' }],
    ['list']
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
        // Remove trailing slash so page.goto('/') works correctly
        baseURL: process.env.DEPLOYED_URL?.replace(/\/$/, '') || 'https://fede2cr.github.io/azure-support-scripts',
      },
    },
  ],

  webServer: process.env.BASE_URL ? undefined : {
    command: 'npx http-server ../ -p 8080',
    port: 8080,
    reuseExistingServer: !process.env.CI,
  },
});
