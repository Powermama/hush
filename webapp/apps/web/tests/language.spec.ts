// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Language journeys (docs/user-journeys/language.md): the German landing page,
// first-visit detection from the device language, the remembered choice and
// the footer switcher.
import { expect, test } from "@playwright/test";

test.use({ locale: "en-US" });

test("LANG-001 prerenders the German landing page with its own metadata and hreflang", async ({ browser }) => {
  const context = await browser.newContext({ javaScriptEnabled: false, locale: "en-US" });
  const page = await context.newPage();
  expect((await page.goto("/de"))!.status()).toBe(200);
  await expect(page.locator("html")).toHaveAttribute("lang", "de");
  await expect(page.locator("h1")).toHaveText("Die Sprachebene für deinen Mac.");
  await expect(page.locator('meta[property="og:locale"]')).toHaveAttribute("content", "de_DE");
  // German download buttons say "Download", as German Mac users expect, never "Laden".
  const html = await page.content();
  expect(html).toContain("Download für Mac");
  expect(html).not.toMatch(/>\s*(Für den Mac laden|Laden)\s*</);
  for (const [lang, href] of [["en", "https://behu.sh/"], ["de", "https://behu.sh/de"], ["x-default", "https://behu.sh/"]] as const) {
    await expect(page.locator(`link[rel="alternate"][hreflang="${lang}"]`)).toHaveAttribute("href", href);
  }
  const data = JSON.parse((await page.locator('script[type="application/ld+json"]').allInnerTexts())[0]!);
  expect(data).toMatchObject({ "@type": "SoftwareApplication", inLanguage: "de", url: "https://behu.sh/de", offers: { price: "0" } });
  await page.goto("/");
  await expect(page.locator('link[rel="alternate"][hreflang="de"]')).toHaveAttribute("href", "https://behu.sh/de");
  await context.close();
});

test("LANG-002 sends a German device to /de on its first visit to the home page only", async ({ browser }) => {
  const german = await browser.newContext({ locale: "de-DE" });
  const page = await german.newPage();
  await page.goto("/");
  await expect(page).toHaveURL(/\/de$/);
  await expect(page.locator("h1")).toHaveText("Die Sprachebene für deinen Mac.");
  // Deep links are never redirected.
  await page.goto("/verified-messages");
  await expect(page).toHaveURL(/\/verified-messages$/);
  await german.close();
  const english = await browser.newContext({ locale: "en-US" });
  const englishPage = await english.newPage();
  await englishPage.goto("/");
  await expect(englishPage).toHaveURL(/\/$/);
  await expect(englishPage.locator(".language-hint")).toHaveCount(0);
  await english.close();
});

test("LANG-003 remembers the language chosen in the footer over the device language", async ({ browser }) => {
  const german = await browser.newContext({ locale: "de-DE" });
  const page = await german.newPage();
  await page.goto("/de");
  const switcher = page.locator("footer").getByRole("navigation", { name: "Sprache" });
  await expect(switcher.getByRole("link", { name: "Deutsch" })).toHaveAttribute("aria-current", "true");
  await switcher.getByRole("link", { name: "English" }).click();
  // Let the switch finish loading: starting another navigation while it is
  // still in flight sometimes crashes WebKit ("internal error") in CI.
  await page.waitForURL(/\/$/, { waitUntil: "load" });
  await page.goto("/");
  await expect(page).toHaveURL(/\/$/);
  await expect(page.locator("h1")).toHaveText("The voice layer for your Mac.");
  await german.close();
});

test("LANG-004 offers the other language in a dismissible bar", async ({ page }) => {
  await page.goto("/de");
  const hint = page.locator(".language-hint");
  await expect(hint).toContainText("This page is also available in English.");
  await hint.getByRole("button", { name: "Dismiss" }).click();
  await expect(hint).toHaveCount(0);
  await page.reload();
  await expect(page.locator(".language-hint")).toHaveCount(0);
  await expect(page).toHaveURL(/\/de$/);
});

test("LANG-005 keeps the German landing design identical to the English one", async ({ browser }) => {
  const sizes = async (path: string) => {
    const context = await browser.newContext({ locale: path === "/de" ? "de-DE" : "en-US" });
    const page = await context.newPage();
    await page.goto(path);
    const result = await page.evaluate(() => ["#hero-title", "#thought-title", "#freedom-title", "#intelligence-title", "#provenance-title", "#faq-title", ".landing-final h2"]
      .map((selector) => getComputedStyle(document.querySelector(selector)!).fontSize));
    await context.close();
    return result;
  };
  expect(await sizes("/de")).toEqual(await sizes("/"));
});
