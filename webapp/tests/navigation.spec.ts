import { expect, test } from "@playwright/test";

test("LANDING-NAV-001 shares clear navigation across public pages", async ({ page, isMobile }, testInfo) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  for (const path of ["/", "/verified-messages", "/releases", "/datenschutz"]) {
    await page.goto(path);
    const header = page.locator(".site-header");
    await expect(header).toHaveCount(1);
    if (isMobile) {
      await expect(header.getByRole("link", { name: "Verified Messages", exact: true })).toBeHidden();
      await header.getByRole("button", { name: "Open navigation" }).click();
    }
    await expect(header.getByRole("link", { name: "GitHub" })).toHaveAttribute("href", "https://github.com/Powermama/hush");
    await expect(header.getByRole("link", { name: "GitHub" })).toHaveAttribute("rel", "noopener noreferrer");
    await expect(header.getByRole("button", { name: "Community, coming soon" })).toBeDisabled();
    await expect(header.getByRole("link", { name: "Verified Messages", exact: true })).toBeVisible();
    await expect(header.getByRole(isMobile ? "button" : "link", { name: isMobile ? "Get hush for Mac" : "Download", exact: true })).toBeVisible();
    await expect(header.getByRole("link", { name: /Privacy|What’s new/ })).toHaveCount(0);
    expect(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth)).toBe(false);
    await header.screenshot({ path: testInfo.outputPath(`header-${path.replaceAll("/", "") || "home"}.png`) });
  }
  await page.locator(".site-header").getByRole("link", { name: "Verified Messages", exact: true }).click();
  await expect(page).toHaveURL(/\/verified-messages$/);
  await expect(page.locator('.site-header [aria-current="page"]')).toHaveText("Verified Messages");
});

test("mobile navigation stays compact and closes with Escape or outside interaction", async ({ page }, testInfo) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  for (const width of [320, 390, 760]) {
    await page.setViewportSize({ width, height: 844 });
    await page.goto("/");
    const header = page.locator(".site-header");
    expect((await header.boundingBox())!.height).toBeLessThan(90);
    const toggle = header.getByRole("button", { name: "Open navigation" });
    expect((await toggle.boundingBox())!.width).toBeGreaterThanOrEqual(44);
    const start = header.locator(".site-compact-download");
    await expect(start).toBeVisible();
    const startBox = (await start.boundingBox())!, toggleBox = (await toggle.boundingBox())!;
    expect(startBox.x + startBox.width).toBeLessThanOrEqual(toggleBox.x - 7);
    expect(startBox.x).toBeGreaterThan(55);
    await toggle.click();
    await expect(start).toBeHidden();
    await expect(header.getByRole("link", { name: "GitHub" })).toBeVisible();
    const expanded = (await header.boundingBox())!;
    expect(Math.round(expanded.height)).toBeGreaterThanOrEqual(844);
    const menuDownload = header.locator(".site-header-download");
    const downloadBox = (await menuDownload.boundingBox())!;
    expect(downloadBox.width).toBeGreaterThan(width - 50);
    expect(downloadBox.height).toBeGreaterThanOrEqual(56);
    expect((await menuDownload.locator("svg").boundingBox())!.width).toBeGreaterThanOrEqual(20);
    const hero = (await page.getByRole("heading", { level: 1 }).boundingBox())!;
    expect(hero.y).toBeGreaterThan(expanded.y + expanded.height);
    await page.screenshot({ path: testInfo.outputPath(`mobile-menu-${width}.png`) });
    await page.keyboard.press("Escape");
    await expect(toggle).toBeFocused();
    await expect(toggle).toHaveAttribute("aria-expanded", "false");
    await expect(start).toBeVisible();
    await toggle.click();
    await page.getByRole("heading", { level: 1 }).click();
    await expect(toggle).toHaveAttribute("aria-expanded", "false");
    expect(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth)).toBe(false);
    await page.screenshot({ path: testInfo.outputPath(`mobile-header-${width}.png`) });
  }
});

test("LANDING-NAV-002 scrolls the header away and shows only a progress line", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/datenschutz");
  const progress = page.getByRole("progressbar", { name: "Page reading progress" });
  await expect(progress).toHaveAttribute("aria-valuenow", "0");
  await expect(progress).toHaveCSS("opacity", "0");
  await page.evaluate(() => scrollTo(0, (document.documentElement.scrollHeight - innerHeight) / 2));
  await expect(progress).toHaveAttribute("aria-valuenow", "50");
  await expect(progress).toHaveCSS("opacity", "1");
  expect((await page.locator(".site-header").boundingBox())!.y).toBeLessThan(0);
  expect((await progress.boundingBox())!.y).toBe(0);
  await expect(progress.locator("button, a, .page-progress-stops")).toHaveCount(0);
  await page.evaluate(() => scrollTo(0, document.documentElement.scrollHeight));
  await expect(progress).toHaveAttribute("aria-valuenow", "100");
  await page.evaluate(() => scrollTo(0, 0));
  await expect(progress).toHaveAttribute("aria-valuenow", "0");
});
