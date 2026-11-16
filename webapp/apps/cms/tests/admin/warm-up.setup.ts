// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Runs before the WebKit journeys (a setup project, playwright.config.ts). On a
// fresh Linux machine, such as every CI run, WebKit renders in software (Mesa
// llvmpipe) and compiles its shaders and font caches the first time it draws a
// page, into ~/.cache. Without this, that one-time cost of several seconds lands
// in whichever journey draws first and pushes it past its timeout. Drawing the
// editor and its preview once here fills those caches; it asserts nothing about
// the admin, the journeys do.
import { expect, test as setup } from "@playwright/test";
import { validPost } from "../fixtures";

setup("WebKit draws the editor and its preview once", async ({ page }) => {
  setup.slow();
  await page.goto("/__e2e/sign-in");
  await expect(page.getByRole("heading", { name: "Posts", exact: true })).toBeVisible();
  const slug = `warm-up-${Date.now().toString(36)}`;
  const response = await page.request.post("/v1/posts", { data: validPost({ slug, keyword: slug.replaceAll("-", " ") }) });
  expect(response.status()).toBe(201);
  const { id } = await response.json() as { id: string };

  await page.goto(`/posts/${id}`);
  const article = page.getByRole("textbox", { name: "Article" });
  await article.locator("p").last().click();
  await page.keyboard.type(" Warm.");
  await page.keyboard.press("ControlOrMeta+p");
  await expect(page.frameLocator("iframe[title=Preview]").getByText("Warm.")).toBeVisible();
  await page.keyboard.press("Escape");
  // Not left behind as a draft other journeys would list. With the admin's
  // Origin, as its own requests carry it: the CSRF check refuses a cookie
  // request without one.
  const deleted = await page.request.delete(`/v1/posts/${id}`, { headers: { origin: new URL(page.url()).origin } });
  expect(deleted.status()).toBe(204);
});
