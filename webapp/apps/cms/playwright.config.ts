// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Browser journeys of the admin (CMS-001 to CMS-010), against the CMS serving
// the built admin. Build it first: bun run --cwd ../cms-admin build.
import { defineConfig, devices } from "@playwright/test";

// Another port (CMS_ADMIN_E2E_PORT) lets two checkouts run their journeys at once.
const port = Number(process.env.CMS_ADMIN_E2E_PORT ?? 4310);

export default defineConfig({
  testDir: "./tests/admin",
  // bun test runs *.test.ts and *.spec.ts; the browser journeys stay out of it.
  testMatch: "*.e2e.ts",
  fullyParallel: true,
  forbidOnly: Boolean(process.env.CI),
  // One retry in CI, as Playwright's own template; a journey that needs it is
  // reported as flaky, never as passed, so the report still shows it.
  retries: process.env.CI ? 1 : 0,
  reporter: "line",
  use: {
    // HTTPS on localhost with the test server's self-signed certificate, as in production.
    baseURL: `https://localhost:${port}`,
    ignoreHTTPSErrors: true,
    trace: "retain-on-failure",
  },
  projects: [
    { name: "desktop", use: { ...devices["Desktop Chrome"] } },
    { name: "mobile", use: { ...devices["iPhone 13"], browserName: "chromium" } },
    // WebKit's first page on a fresh machine pays one-time shader and font
    // caching; tests/admin/warm-up.setup.ts pays it before the journeys.
    { name: "webkit warm-up", testMatch: "warm-up.setup.ts", use: { ...devices["Desktop Safari"] } },
    { name: "webkit", use: { ...devices["Desktop Safari"] }, dependencies: ["webkit warm-up"] },
  ],
  webServer: {
    command: `PORT=${port} bun run admin:server`,
    url: `https://localhost:${port}/health/live`,
    ignoreHTTPSErrors: true,
    reuseExistingServer: false,
  },
});
