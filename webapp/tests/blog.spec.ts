// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Blog journeys (docs/user-journeys/blog.md). They run against the fixture
// articles: CI generates them with
//   HUSH_BLOG_CONTENT_DIR=scripts/blog/fixtures/content bun run blog:generate
// before building. With the committed content they skip.
import { expect, test } from "@playwright/test";
import { blogPosts } from "../shared/blog-posts.generated";

const article = "/blog/fixture-dictation-without-cloud";
test.skip(!blogPosts.some((post) => post.slug === "fixture-dictation-without-cloud"), "fixture articles are not generated");

test("BLOG-001 reads a prerendered article without JavaScript", async ({ browser }) => {
  const context = await browser.newContext({ javaScriptEnabled: false });
  const page = await context.newPage();
  const response = await page.goto(article);
  expect(response!.status()).toBe(200);
  await expect(page.locator("h1")).toHaveCount(1);
  await expect(page.locator("h1")).toHaveText("Fixture article body heading");
  await expect(page.getByText("This fixture paragraph answers the question first.")).toBeVisible();
  await expect(page.locator('meta[property="og:type"]')).toHaveAttribute("content", "article");
  const data = JSON.parse(await page.locator('script[type="application/ld+json"]').innerText());
  expect(data).toMatchObject({
    "@type": "BlogPosting", headline: "Fixture article body heading",
    datePublished: "2026-11-01T00:00:00Z", dateModified: "2026-11-10T00:00:00Z",
    author: { "@type": "Person", name: "Clemens Kressmann", url: "https://behu.sh/authors/clemens-kressmann" },
  });
  await context.close();
});

test("BLOG-002 hydrates without errors and keeps the article", async ({ page }) => {
  const problems: string[] = [];
  page.on("pageerror", (error) => problems.push(error.message));
  page.on("console", (message) => { if (message.type() === "error") problems.push(message.text()); });
  await page.goto(article);
  await page.waitForLoadState("networkidle");
  await expect(page.getByText("This fixture paragraph answers the question first.")).toBeVisible();
  expect(problems).toEqual([]);
});

test("BLOG-003 offers the right download action for the device", async ({ page, isMobile }) => {
  await page.goto(article);
  const cta = page.locator(".blog-cta");
  if (isMobile) {
    // Phones get the send-to-Mac handoff, never a disk image.
    await expect(cta.getByRole("button", { name: "Get hush for Mac" })).toBeVisible();
    await expect(cta.locator('a[href$=".dmg"]')).toHaveCount(0);
  } else {
    await expect(cta.getByRole("link", { name: "Download for Mac" })).toBeVisible();
  }
});

test("BLOG-004 navigates with the table of contents and related articles", async ({ page, isMobile }) => {
  await page.goto(article);
  if (isMobile) await page.locator(".blog-toc-mobile summary").click();
  const toc = page.locator(isMobile ? ".blog-toc-mobile" : ".blog-toc-desktop");
  await toc.getByRole("link", { name: "Frequently asked questions" }).click();
  await expect(page).toHaveURL(/#frequently-asked-questions$/);
  await page.locator(".blog-related").getByRole("link", { name: /Second fixture heading/ }).click();
  await expect(page).toHaveURL(/\/blog\/fixture-dictation-commands$/);
  await expect(page.getByText("The second fixture links back")).toBeVisible();
});

test("BLOG-005 lists articles per language and keeps drafts and unknown slugs out", async ({ page, request }) => {
  await page.goto("/blog");
  await expect(page.getByRole("heading", { level: 1, name: "The hush blog" })).toBeVisible();
  await expect(page.locator(".blog-index-list li")).toHaveCount(2);
  await page.goto("/de/blog");
  await expect(page.getByRole("heading", { level: 1, name: "Der hush Blog" })).toBeVisible();
  await expect(page.locator("html")).toHaveAttribute("lang", "de");
  for (const path of ["/blog/fixture-draft", "/blog/does-not-exist"]) {
    expect((await request.get(path)).status()).toBe(404);
  }
  const sitemap = await (await request.get("/sitemap.xml")).text();
  expect(sitemap).toContain("/blog/fixture-dictation-without-cloud");
  expect(sitemap).not.toContain("fixture-draft");
  const feed = await request.get("/blog/feed.xml");
  expect(feed.status()).toBe(200);
  expect(await feed.text()).toContain("<title>Fixture article body heading</title>");
});

test("BLOG-006 never scrolls sideways and applies no runtime filters", async ({ page }) => {
  await page.goto(article);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true);
  const filtered = await page.evaluate(() => [...document.querySelectorAll("*")]
    .filter((element) => getComputedStyle(element).filter !== "none")
    .map((element) => element.tagName));
  expect(filtered).toEqual([]);
});

test("BLOG-007 links bylines to a prerendered author profile with ProfilePage data", async ({ browser, page }) => {
  const context = await browser.newContext({ javaScriptEnabled: false });
  const plain = await context.newPage();
  expect((await plain.goto("/authors/clemens-kressmann"))!.status()).toBe(200);
  await expect(plain.locator("h1")).toHaveText("Clemens Kressmann");
  await expect(plain.locator('meta[property="og:type"]')).toHaveAttribute("content", "profile");
  const data = JSON.parse(await plain.locator('script[type="application/ld+json"]').innerText());
  expect(data).toMatchObject({
    "@type": "ProfilePage",
    mainEntity: { "@type": "Person", name: "Clemens Kressmann", url: "https://behu.sh/authors/clemens-kressmann",
      sameAs: ["https://www.linkedin.com/in/clemens-kressmann/", "https://github.com/Powermama"] },
  });
  await expect(plain.locator(".blog-index-list li")).toHaveCount(2);
  await context.close();

  await page.goto(article);
  await page.locator(".blog-byline").getByRole("link", { name: "Clemens Kressmann" }).click();
  await expect(page).toHaveURL(/\/authors\/clemens-kressmann$/);
  await expect(page.locator(".blog-author-links").getByRole("link", { name: /LinkedIn/ })).toHaveAttribute("rel", "me noopener");
  expect((await page.request.get("/de/autoren/clemens-kressmann")).status()).toBe(200);
});
