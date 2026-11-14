// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Browser journeys of the admin (CMS-001 to CMS-008), against the CMS serving
// the built admin. Build it first: bun run --cwd ../cms-admin build.
import { defineConfig, devices } from "@playwright/test";

const port = 4310;

export default defineConfig({
  testDir: "./tests/admin",
  // bun test runs *.test.ts and *.spec.ts; the browser journeys stay out of it.
  testMatch: "*.e2e.ts",
  fullyParallel: true,
  forbidOnly: Boolean(process.env.CI),
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
    { name: "webkit", use: { ...devices["Desktop Safari"] } },
  ],
  webServer: {
    command: `PORT=${port} bun run admin:server`,
    url: `https://localhost:${port}/health/live`,
    ignoreHTTPSErrors: true,
    reuseExistingServer: false,
  },
});
