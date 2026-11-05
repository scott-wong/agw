import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: '.',
  timeout: 30000,
  workers: 1,
  reporter: 'line',
  use: {
    baseURL: process.env.AGW_UI_BASE_URL ?? 'http://127.0.0.1:19180',
    ignoreHTTPSErrors: true,
    trace: 'retain-on-failure',
  },
});
