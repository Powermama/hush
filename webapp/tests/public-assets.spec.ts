// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { expect, test } from "@playwright/test";

test("LANDING-CACHE-001 uses versioned artwork while keeping public HTML fresh", async ({ page, request }) => {
  for (const path of ["/", "/verified-messages"]) {
    const response = await page.goto(path);
    expect(response!.headers()["cache-control"]).toBe("no-cache, must-revalidate");
    const image = path === "/" ? page.locator(".orbit-mail img") : page.locator(".vm-portrait-fallback img");
    const source = await image.getAttribute("src");
    expect(source).toMatch(/^\/assets\/[\w-]+\.(png|webp)$/);
    // The prerendered HTML and hydrated image must reference the same version.
    expect(await response!.text()).toContain(source!);
    await expect.poll(() => image.evaluate((element: HTMLImageElement) => element.complete && element.naturalWidth > 0)).toBe(true);
    const asset = await request.get(source!);
    expect(asset.status()).toBe(200);
    expect(asset.headers()["cache-control"]).toBe("public, max-age=31536000, immutable");
    const resolved = await image.evaluate((element: HTMLImageElement) => element.currentSrc);
    expect(new URL(resolved).origin).toBe(new URL(page.url()).origin);
  }
});

test("LANDING-CACHE-002 retains responsive artwork and its public attribution", async ({ page, request }) => {
  await page.goto("/");
  const image = page.locator(".portrait-base img");
  await image.scrollIntoViewIfNeeded();
  await expect.poll(() => image.evaluate((element: HTMLImageElement) => element.complete && element.naturalWidth > 0)).toBe(true);
  const candidates = (await image.getAttribute("srcset"))!.split(", ");
  expect(candidates).toHaveLength(2);
  for (const candidate of candidates) {
    const [url] = candidate.split(" ");
    expect(url).toMatch(/^\/assets\/aristotle(?:-small)?-[\w-]+\.webp$/);
    const response = await request.get(url!);
    expect(response.status()).toBe(200);
    expect(response.headers()["cache-control"]).toContain("immutable");
  }
  expect((await request.get("/art/CREDITS.md")).status()).toBe(200);
});
