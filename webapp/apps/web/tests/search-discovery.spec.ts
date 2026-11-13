// SPDX-License-Identifier: AGPL-3.0-only
// Copyright 2026 Clemens Kressmann
import { expect, test } from "@playwright/test";

test("public pages provide readable content and unique previews without JavaScript", async ({ browser, request }) => {
  const context = await browser.newContext({ javaScriptEnabled: false });
  const page = await context.newPage();
  try {
    for (const [path, title, heading, image] of [
      ["/", "hush - Free Dictation App for Mac, Speech to Text", "The voice layer for your Mac.", "hush"],
      ["/verified-messages", "Verified Messages - Signed message history with hush", "Make your voice more than a post.", "verified-messages"],
    ]) {
      const response = await page.goto(`${test.info().project.use.baseURL}${path}`);
      expect(response?.status()).toBe(200);
      await expect(page).toHaveTitle(title!);
      expect((await page.locator("h1").innerText()).replace(/\s+/g, " ")).toBe(heading);
      await expect(page.locator("h1")).toBeVisible();
      await expect(page.locator('link[rel="canonical"]')).toHaveAttribute("href", `https://behu.sh${path}`);
      await expect(page.locator('meta[property="og:title"]')).toHaveAttribute("content", title!);
      await expect(page.locator('meta[property="og:url"]')).toHaveAttribute("content", `https://behu.sh${path}`);
      await expect(page.locator('meta[property="og:image"]')).toHaveAttribute("content", `https://behu.sh/social/${image}.png`);
      await expect(page.locator('meta[name="twitter:card"]')).toHaveAttribute("content", "summary_large_image");
      // The product links, not the language switcher, which may also point to this page.
      await expect(page.locator("footer").getByRole("link", { name: "Verified Messages" })).toBeVisible();
      const preview = await request.get(`/social/${image}.png`);
      expect(preview.status()).toBe(200);
      expect(preview.headers()["content-type"]).toContain("image/png");
      const bytes = await preview.body();
      expect(bytes.readUInt32BE(16)).toBe(1200);
      expect(bytes.readUInt32BE(20)).toBe(630);
    }
    await page.goto(`${test.info().project.use.baseURL}/`);
    const homeData = (await page.locator('script[type="application/ld+json"]').allInnerTexts()).map((text) => JSON.parse(text));
    const application = homeData.find((data) => data["@type"] === "SoftwareApplication");
    expect(application).toMatchObject({ "@type": "SoftwareApplication", name: "hush", operatingSystem: "macOS 15 or later" });
    expect(application).not.toHaveProperty("aggregateRating");
    for (const [path, language, alternate] of [["/impressum", "en", "/de/impressum"], ["/de/impressum", "de", "/impressum"]]) {
      await page.goto(`${test.info().project.use.baseURL}${path}`);
      await expect(page.locator("html")).toHaveAttribute("lang", language!);
      await expect(page.locator("address")).toBeVisible();
      await expect(page.locator(`link[hreflang="${language === "de" ? "en" : "de"}"]`)).toHaveAttribute("href", `https://behu.sh${alternate}`);
    }
  } finally { await context.close(); }
});

test("hydrates under the existing CSP without losing the public page", async ({ page }) => {
  const errors: string[] = [];
  page.on("pageerror", error => errors.push(error.message));
  page.on("console", message => { if (message.type() === "error") errors.push(message.text()); });
  await page.emulateMedia({ reducedMotion: "reduce" });
  for (const path of ["/", "/verified-messages", "/impressum", "/de/datenschutz", "/releases"]) {
    const response = await page.goto(path);
    expect(response?.headers()["content-security-policy"]).not.toContain("script-src 'self' 'unsafe-inline'");
    await expect(page.locator("h1")).toBeVisible();
    await expect(page.locator('meta[property="og:title"]')).toHaveAttribute("content", await page.title());
    await page.waitForTimeout(250);
  }
  expect(errors).toEqual([]);
});

test("keeps discovery public, preserves private no-store and returns genuine 404s", async ({ request }) => {
  const sitemap = await (await request.get("/sitemap.xml")).text();
  expect(sitemap).toContain("https://behu.sh/verified-messages");
  expect(sitemap).not.toMatch(/\/p\/|\/s\/|\/v1\/|alpha|datenschutz/);
  const llms = await (await request.get("/llms.txt")).text();
  expect(llms).toMatch(/^# hush\n/);
  expect(llms).toContain("https://github.com/Powermama/hush");
  expect(llms).not.toMatch(/https:\/\/behu.sh\/(p|s|v1)\//);
  for (const path of ["/p/unknown", "/releases/0.1.0-alpha.5", "/impressum"]) {
    const response = await request.get(path);
    expect(response.headers()["x-robots-tag"]).toBe("noindex, nofollow");
    expect(response.headers()["cache-control"]).toBe("no-store");
    expect(await response.text()).toContain('name="robots" content="noindex, nofollow"');
  }
  for (const path of ["/missing-page-that-does-not-exist", "/releases/missing", "/dist-pages/pages.json"]) {
    expect((await request.get(path)).status()).toBe(404);
  }
  expect((await request.get("/index.html", { maxRedirects: 0 })).headers().location).toBe("/");
});

test("SEARCH-004 names the site and shows its icon and logo wherever search engines and devices look", async ({ page, request }) => {
  await page.goto("/");
  for (const [selector, href] of [
    ['link[rel="icon"][sizes="48x48"]', "/favicon.ico"],
    ['link[rel="icon"][type="image/svg+xml"]', "/favicon.svg"],
    ['link[rel="icon"][sizes="96x96"]', "/favicon-96x96.png"],
    ['link[rel="apple-touch-icon"]', "/apple-touch-icon.png"],
  ]) await expect(page.locator(selector!)).toHaveAttribute("href", href!);
  for (const [path, type, size] of [
    ["/favicon.ico", "image/", 0], ["/favicon-96x96.png", "image/png", 96], ["/apple-touch-icon.png", "image/png", 180], ["/logo.png", "image/png", 512],
  ] as const) {
    const response = await request.get(path);
    expect(response.status(), path).toBe(200);
    expect(response.headers()["content-type"], path).toContain(type);
    if (size) expect((await response.body()).readUInt32BE(16), path).toBe(size);
  }
  const data = (await page.locator('script[type="application/ld+json"]').allInnerTexts()).map((text) => JSON.parse(text));
  expect(data.find((item) => item["@type"] === "WebSite")).toMatchObject({ name: "hush", url: "https://behu.sh/" });
  expect(data.find((item) => item["@type"] === "Organization")).toMatchObject({
    name: "hush", logo: { url: "https://behu.sh/logo.png", width: 512, height: 512 },
  });
});
