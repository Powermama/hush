// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { expect, test } from "@playwright/test";
import { createServer, type ViteDevServer } from "vite";

let vite: ViteDevServer;
let origin: string;

test.beforeAll(async () => {
  vite = await createServer({ server: { host: "127.0.0.1", port: 0 } });
  await vite.listen();
  const address = vite.httpServer!.address();
  if (!address || typeof address === "string") throw new Error("Vite did not bind a local port");
  origin = `http://127.0.0.1:${address.port}`;
});

test.afterAll(async () => { await vite?.close(); });

test("Vite preview renders the 3D hero and rose with HTTP-decoded lighting", async ({ page }, testInfo) => {
  const errors: string[] = [];
  page.on("pageerror", error => errors.push(error.message));
  await page.emulateMedia({ reducedMotion: "reduce" });
  const lightingResponse = page.waitForResponse(response => response.url().endsWith("studio-lighting.ktx2.gz"));
  await page.goto(origin);
  const response = await lightingResponse;
  expect(response.headers()["content-encoding"]).toBe("gzip");
  await expect(page.locator(".hush-core")).toHaveAttribute("data-scene", "ready", { timeout: 15000 });
  await expect(page.locator(".hush-core canvas")).toHaveCSS("opacity", "1");
  const rose = page.locator(".freedom-bloom");
  await rose.scrollIntoViewIfNeeded();
  await expect(rose).toHaveAttribute("data-scene", "ready", { timeout: 15000 });
  await expect(rose.locator("canvas")).toBeVisible();
  await expect(rose.locator(".bloom-fallback")).toHaveCSS("opacity", "0");
  expect(errors).toEqual([]);
  await page.screenshot({ path: testInfo.outputPath("vite-3d-rose.png") });
});
