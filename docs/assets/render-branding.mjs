// SPDX-License-Identifier: AGPL-3.0-only
// Copyright 2026 Clemens Kressmann
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

// Reuse the website's pinned Playwright dependency. No separate toolchain.
const require = createRequire(new URL("../../webapp/package.json", import.meta.url));
const { chromium } = require("@playwright/test");
const browser = await chromium.launch();
try {
  const page = await browser.newPage({ viewport: { width: 1280, height: 640 }, deviceScaleFactor: 1 });
  await page.route(/^https?:/, route => route.abort());
  await page.goto(new URL("github-social.html", import.meta.url).href);
  await page.evaluate(async () => {
    await document.fonts.ready;
    await Promise.all([...document.images].map(image => image.decode()));
  });
  await page.screenshot({ path: fileURLToPath(new URL("github-social.png", import.meta.url)) });
} finally {
  await browser.close();
}
