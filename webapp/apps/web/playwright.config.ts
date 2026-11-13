import { defineConfig, devices } from "@playwright/test";

const baseURL = process.env.HUSH_E2E_BASE_URL ?? "http://127.0.0.1:4173";
if (!/^http:\/\/127\.0\.0\.1:\d+$/.test(baseURL)) {
  throw new Error("HUSH_E2E_BASE_URL must be an HTTP 127.0.0.1 URL with a port");
}
const port = new URL(baseURL).port;

export default defineConfig({
  testDir: "./tests",
  fullyParallel: true,
  // Shared CI runners must not contend over software-rendered WebGL contexts.
  // https://playwright.dev/docs/ci#workers
  workers: process.env.CI ? 1 : undefined,
  forbidOnly: Boolean(process.env.CI),
  globalTimeout: process.env.CI ? 15 * 60 * 1000 : undefined,
  reporter: "line",
  use: {
    baseURL,
    trace: "retain-on-failure",
  },
  projects: [
    {
      name: "desktop",
      use: { ...devices["Desktop Chrome"] },
    },
    {
      name: "mobile",
      use: { ...devices["iPhone 13"], browserName: "chromium" },
    },
    {
      name: "webkit",
      use: { ...devices["Desktop Safari"] },
    },
  ],
  webServer: {
    command: `NODE_ENV=test PORT=${port} HUSH_PUBLIC_BASE_URL=${baseURL} bun server/index.ts`,
    url: `${baseURL}/health/ready`,
    reuseExistingServer: false,
  },
});
