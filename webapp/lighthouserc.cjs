// SPDX-License-Identifier: AGPL-3.0-only
// Copyright 2026 Clemens Kressmann
module.exports = {
  ci: {
    collect: {
      url: ["http://127.0.0.1:4315/", "http://127.0.0.1:4315/verified-messages"],
      numberOfRuns: 1,
      startServerCommand: "NODE_ENV=test PORT=4315 HUSH_PUBLIC_BASE_URL=http://127.0.0.1:4315 bun server/index.ts",
      startServerReadyPattern: "proof service listening",
      chromePath: process.env.CHROME_PATH || require("@playwright/test").chromium.executablePath(),
      settings: { onlyCategories: ["seo"], chromeFlags: "--headless" },
    },
    assert: {
      assertions: { "categories:seo": ["error", { minScore: 1 }] },
    },
    // Reports remain local. No upload target, tokens or new scheduled runners.
  },
};
