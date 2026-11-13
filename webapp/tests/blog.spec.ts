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
  const scripts = await page.locator('script[type="application/ld+json"]').allInnerTexts();
  const data = JSON.parse(scripts[0]!);
  expect(JSON.parse(scripts.at(-1)!)).toMatchObject({
    "@type": "BreadcrumbList",
    itemListElement: [
      { position: 1, name: "hush", item: "https://behu.sh/" },
      { position: 2, name: "The hush blog", item: "https://behu.sh/blog" },
      { position: 3, name: "Fixture article body heading" },
    ],
  });
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
  const cta = page.locator(".blog-download-band");
  if (isMobile) {
    // Phones get the send-to-Mac handoff, never a disk image.
    await expect(cta.getByRole("button", { name: "Get hush for Mac" })).toBeVisible();
    await expect(cta.locator('a[href$=".dmg"]')).toHaveCount(0);
  } else {
    await expect(cta.getByRole("link", { name: "Download for Mac" })).toBeVisible();
  }
});

test("BLOG-004 links section headings and continues to related articles", async ({ page }) => {
  // No contents sidebar: headings carry their own anchors for links and search results.
  await page.goto(`${article}#frequently-asked-questions`);
  await expect(page.locator("#frequently-asked-questions")).toBeInViewport();
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
  const data = JSON.parse((await plain.locator('script[type="application/ld+json"]').allInnerTexts())[0]!);
  expect(data).toMatchObject({
    "@type": "ProfilePage",
    mainEntity: { "@type": "Person", name: "Clemens Kressmann", url: "https://behu.sh/authors/clemens-kressmann",
      image: "https://behu.sh/media/authors/clemens-kressmann.webp",
      sameAs: ["https://www.linkedin.com/in/clemens-kressmann/", "https://github.com/Powermama"] },
  });
  await expect(plain.locator(".blog-index-list li")).toHaveCount(2);
  expect((await plain.request.get("/media/authors/clemens-kressmann.webp")).headers()["content-type"]).toBe("image/webp");
  await context.close();

  await page.goto(article);
  await page.locator(".blog-article-header .blog-byline").click();
  await expect(page).toHaveURL(/\/authors\/clemens-kressmann$/);
  await expect(page.locator(".blog-author-links").getByRole("link", { name: /LinkedIn/ })).toHaveAttribute("rel", "me noopener");
  expect((await page.request.get("/de/autoren/clemens-kressmann")).status()).toBe(200);
});

test("BLOG-008 keeps the way back and sharing in a quiet margin, with no contents sidebar", async ({ page, isMobile }) => {
  for (const path of [article, "/blog/fixture-dictation-commands"]) {
    await page.goto(path);
    await expect(page.locator("nav.blog-toc, .blog-sidebar, details.blog-toc-mobile")).toHaveCount(0);
    const back = await page.locator(".blog-article > .blog-back").boundingBox();
    // The chevron is an inline 16px icon, never a full-size SVG.
    expect((await page.locator(".blog-article > .blog-back .blog-arrow").boundingBox())!.width).toBeLessThanOrEqual(16);
    expect(back!.height).toBeLessThan(30);
    const prose = await page.locator(".blog-prose").boundingBox();
    if (isMobile) {
      await expect(page.locator(".blog-share-margin")).toBeHidden();
      await expect(page.locator(".blog-share-end").getByRole("button").first()).toBeVisible();
    } else {
      // As on Notion: back link and sharing sit left of the text column.
      expect(back!.x + back!.width).toBeLessThan(prose!.x);
      const share = page.locator(".blog-share-margin");
      await expect(share.getByRole("link", { name: "Share on LinkedIn" })).toBeVisible();
      expect((await share.boundingBox())!.x + (await share.boundingBox())!.width).toBeLessThan(prose!.x);
      await expect(page.locator(".blog-share-end")).toBeHidden();
    }
  }
});

test("BLOG-009 serves the article artwork only as a social preview", async ({ page, request }) => {
  await page.goto(article);
  const image = await page.locator('meta[property="og:image"]').getAttribute("content");
  expect(image).toMatch(/^https:\/\/behu\.sh\/blog\/covers\/fixture-dictation-without-cloud-[a-f0-9]{10}-social\.png$/);
  await expect(page.locator('meta[name="twitter:image"]')).toHaveAttribute("content", image!);
  const scripts = await page.locator('script[type="application/ld+json"]').allInnerTexts();
  const data = JSON.parse(scripts[0]!);
  expect(JSON.parse(scripts.at(-1)!)).toMatchObject({
    "@type": "BreadcrumbList",
    itemListElement: [
      { position: 1, name: "hush", item: "https://behu.sh/" },
      { position: 2, name: "The hush blog", item: "https://behu.sh/blog" },
      { position: 3, name: "Fixture article body heading" },
    ],
  });
  expect(data.image).toEqual([image]);
  const response = await request.get(new URL(image!).pathname);
  expect(response.status()).toBe(200);
  expect(response.headers()["content-type"]).toContain("image/png");
  const png = await response.body();
  expect([png.readUInt32BE(16), png.readUInt32BE(20)]).toEqual([1200, 630]);
  await expect(page.locator('img[src*="/blog/covers/"]')).toHaveCount(0);
  await page.goto("/blog");
  await expect(page.locator('img[src*="/blog/covers/"]')).toHaveCount(0);
});

test("BLOG-010 opens a full-size article image in a new tab", async ({ page }) => {
  await page.goto(article);
  const figure = page.locator(".blog-prose figure");
  await figure.scrollIntoViewIfNeeded();
  await expect.poll(() => figure.locator("img").evaluate((img: HTMLImageElement) => img.naturalWidth)).toBeGreaterThan(0);
  const link = figure.getByRole("link", { name: /Open full-size image \(new tab\)/ });
  await expect(link).toHaveAttribute("href", /-900\.webp$/);
  const [popup] = await Promise.all([page.waitForEvent("popup"), link.click()]);
  await expect(popup).toHaveURL(/\/blog\/media\/.+-900\.webp$/);
  await expect.poll(() => popup.locator("img").evaluate((img: HTMLImageElement) => img.naturalWidth)).toBe(900);
  await popup.close();
});

test("BLOG-011 opens the author profile from the padded edge of the author card", async ({ page }) => {
  await page.goto(article);
  await page.locator(".blog-author-card").click({ position: { x: 10, y: 10 } });
  await expect(page).toHaveURL(/\/authors\/clemens-kressmann$/);
  await expect(page.locator("h1")).toHaveText("Clemens Kressmann");
});

test("BLOG-012 preserves selected article text while scrolling", async ({ page }) => {
  await page.goto(article);
  await page.waitForLoadState("networkidle");
  const selected = await page.locator(".blog-prose > p").first().evaluate((paragraph) => {
    const range = document.createRange();
    range.selectNodeContents(paragraph);
    const selection = window.getSelection()!;
    selection.removeAllRanges();
    selection.addRange(range);
    return selection.toString();
  });
  expect(selected).not.toBe("");
  await page.locator("#frequently-asked-questions").evaluate((heading) => heading.scrollIntoView());
  await page.waitForTimeout(300);
  await expect.poll(() => page.evaluate(() => window.getSelection()!.toString())).toBe(selected);
});

test("BLOG-013 explains the editorial policy, linked from the footer", async ({ page, request }) => {
  await page.goto(article);
  await page.locator("footer").getByRole("link", { name: "Editorial policy" }).click();
  await expect(page).toHaveURL(/\/blog\/editorial-policy$/);
  await expect(page.getByRole("heading", { level: 1, name: "Editorial policy" })).toBeVisible();
  await expect(page.getByRole("heading", { level: 2, name: "How we use AI" })).toBeVisible();
  await expect(page.getByText("There are no affiliate links")).toBeVisible();
  expect((await request.get("/de/blog/redaktionelle-richtlinien")).status()).toBe(200);
  expect(await (await request.get("/sitemap.xml")).text()).toContain("/blog/editorial-policy");
});
