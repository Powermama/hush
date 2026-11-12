// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { readFile } from "node:fs/promises";
import { gzipSync } from "node:zlib";
import { expect, test } from "@playwright/test";

test("LANDING-LIGHTING-001 caches the original compressed texture without intermediary transforms", async ({ page }) => {
  const lighting = page.waitForResponse(response => /studio-lighting.*\.gz$/.test(response.url()));
  await page.goto("/");
  const response = await lighting;
  expect(response.headers()["cache-control"]).toBe("public, max-age=31536000, immutable, no-transform");
  expect(response.headers()["content-encoding"]).toBeUndefined();
  await expect(page.locator(".hush-core")).toHaveAttribute("data-scene", "ready", { timeout: 15000 });
});

test("LANDING-LIGHTING-002 renders the hero and rose with legacy edge-compressed lighting", async ({ page }) => {
  const asset = await readFile("src/landing/assets/studio-lighting.ktx2.gz");
  await page.route("**/studio-lighting*.gz", route => route.fulfill({
    // These are the bytes observed after Fetch on the deployed site in WebKit:
    // an edge gzip layer around the already-gzipped KTX2 asset. Deliberately
    // omit Content-Encoding here to reproduce those observable bytes equally
    // in all engines, independently of each engine's HTTP decoding behavior.
    contentType: "application/gzip", body: gzipSync(asset),
  }));
  await page.goto("/");
  await expect(page.locator(".hush-core")).toHaveAttribute("data-scene", "ready", { timeout: 15000 });
  await page.locator(".freedom-bloom").scrollIntoViewIfNeeded();
  await expect(page.locator(".freedom-bloom")).toHaveAttribute("data-scene", "ready", { timeout: 15000 });
  await expect(page.locator(".hush-core canvas")).toHaveCount(1);
  await expect(page.locator(".freedom-bloom canvas")).toHaveCount(1);
});

test("keeps navigation usable when lighting exceeds the supported compression layers", async ({ page }) => {
  const asset = await readFile("src/landing/assets/studio-lighting.ktx2.gz");
  await page.route("**/studio-lighting*.gz", route => route.fulfill({
    contentType: "application/gzip", body: gzipSync(gzipSync(asset)),
  }));
  await page.goto("/");
  await expect(page.locator(".hush-core")).toHaveAttribute("data-scene", "fallback");
  await expect(page.locator(".core-fallback")).toHaveCSS("opacity", "1");
  await expect(page.locator(".hero-actions .landing-download")).toBeVisible();
});
