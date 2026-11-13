// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Not-found journeys (docs/user-journeys/not-found.md): unknown addresses show a
// page with the sad mascot and a way back, in the address's language.
import { expect, test } from "@playwright/test";

test("NOTFOUND-001 answers an unknown address with a 404 page and a way home", async ({ page }) => {
  const response = await page.goto("/this-page-does-not-exist");
  expect(response!.status()).toBe(404);
  await expect(page.locator("h1")).toHaveText("This page got lost.");
  await expect(page).toHaveTitle("Page not found - hush");
  await expect(page.locator('meta[name="robots"]')).toHaveAttribute("content", "noindex, nofollow");
  await expect(page.locator(".hush-mascot-sad")).toBeVisible();
  await expect(page.locator("footer")).toBeVisible();
  await page.getByRole("link", { name: "Back to home" }).click();
  await expect(page).toHaveURL(/\/$/);
});

test("NOTFOUND-002 speaks German under /de", async ({ page }) => {
  const response = await page.goto("/de/gibt-es-nicht");
  expect(response!.status()).toBe(404);
  await expect(page.locator("html")).toHaveAttribute("lang", "de");
  await expect(page.locator("h1")).toHaveText("Diese Seite hat sich verlaufen.");
  await expect(page.getByRole("link", { name: "Zur Startseite" })).toHaveAttribute("href", "/de");
});

test("NOTFOUND-003 keeps JSON errors for API clients", async ({ request }) => {
  for (const path of ["/v1/does-not-exist", "/this-page-does-not-exist"]) {
    const response = await request.get(path, { headers: { accept: "application/json" } });
    expect(response.status()).toBe(404);
    expect((await response.json()).error.code).toBe("not_found");
  }
});
