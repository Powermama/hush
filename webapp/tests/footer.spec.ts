// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { expect, test } from "@playwright/test";

test("LANDING-FOOTER-001 groups mobile links in two left-aligned columns", async ({ page }, testInfo) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  for (const width of [320, 390, 760, 1280]) {
    await page.setViewportSize({ width, height: 844 });
    await page.goto("/verified-messages");
    const footer = page.getByRole("contentinfo");
    await footer.scrollIntoViewIfNeeded();
    const product = footer.getByRole("navigation", { name: "Product", exact: true });
    const legal = footer.getByRole("navigation", { name: "Legal", exact: true });
    const productBox = (await product.boundingBox())!;
    const legalBox = (await legal.boundingBox())!;
    await footer.screenshot({ path: testInfo.outputPath(`footer-${width}.png`) });
    expect(Math.abs(productBox.y - legalBox.y)).toBeLessThan(1);
    expect(productBox.x + productBox.width).toBeLessThan(legalBox.x);
    for (const group of [product, legal]) {
      const box = (await group.boundingBox())!;
      for (const link of await group.getByRole("link").all()) {
        expect((await link.boundingBox())!.x).toBeCloseTo(box.x, 0);
      }
    }
    expect(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth)).toBe(false);
  }
});
