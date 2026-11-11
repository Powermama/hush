import { expect, test } from "@playwright/test";

test("phone visitors can share or copy the Mac link without downloading an installer", async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.addInitScript(() => {
    Object.defineProperty(navigator, "userAgent", { value: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)" });
    Object.defineProperty(navigator, "share", { value: async (data: ShareData) => { document.documentElement.dataset.shared = JSON.stringify(data); } });
    Object.defineProperty(navigator, "clipboard", { value: { writeText: async (text: string) => { document.documentElement.dataset.copied = text; } } });
  });
  const installers: string[] = [], popups: string[] = [];
  page.on("request", request => { if (request.url().endsWith(".dmg")) installers.push(request.url()); });
  page.on("popup", popup => popups.push(popup.url()));
  await page.goto("/");
  const button = page.locator(".landing-download").first();
  await button.focus();
  await button.click();
  const sheet = page.getByRole("dialog", { name: "Meet you on your Mac." });
  await expect(sheet).toBeVisible();
  await expect(sheet.getByText("hush runs on your Mac. Save the link for when you’re there.")).toBeVisible();
  const emailURL = await sheet.getByRole("link", { name: "Email myself the link" }).getAttribute("href");
  expect(emailURL).toMatch(/^mailto:\?/);
  expect(decodeURIComponent(emailURL!)).toContain("https://behu.sh/");
  await sheet.getByRole("button", { name: "Share link", exact: true }).click();
  await expect(page.locator("html")).toHaveAttribute("data-shared", JSON.stringify({ title: "hush for Mac", text: "The voice layer for your Mac.", url: "https://behu.sh/" }));
  await sheet.getByRole("button", { name: "Copy link" }).click();
  await expect(page.locator("html")).toHaveAttribute("data-copied", "https://behu.sh/");
  await expect(sheet.getByRole("status")).toHaveText("Link copied. Open it on your Mac.");
  expect((await sheet.boundingBox())!.width).toBeLessThanOrEqual(390);
  await page.screenshot({ path: testInfo.outputPath("mobile-handoff.png") });
  await sheet.getByRole("button", { name: "Close", exact: true }).click();
  await expect(sheet).toHaveCount(0);
  await expect(button).toBeFocused();
  expect(installers).toEqual([]);
  expect(popups).toEqual([]);
  await button.click();
  await page.keyboard.press("Escape");
  await expect(sheet).toHaveCount(0);
  await expect(page.locator("body")).not.toHaveCSS("overflow", "hidden");
});

test("mobile handoff handles unavailable sharing and denied clipboard access", async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 700 });
  await page.addInitScript(() => {
    Object.defineProperty(navigator, "userAgent", { value: "Mozilla/5.0 Android" });
    Object.defineProperty(navigator, "share", { value: undefined });
    Object.defineProperty(navigator, "clipboard", { value: { writeText: async () => { throw new Error("Clipboard blocked"); } } });
  });
  await page.goto("/");
  await page.getByRole("button", { name: "Open navigation" }).click();
  await page.locator(".site-header-download").click();
  const sheet = page.getByRole("dialog");
  await expect(sheet.getByRole("button", { name: "Share link" })).toHaveCount(0);
  await expect(sheet.getByRole("link", { name: "Email myself the link" })).toBeVisible();
  await sheet.getByRole("button", { name: "Copy link" }).click();
  await expect(sheet.getByRole("textbox", { name: "hush download page" })).toBeFocused();
  await expect(sheet.getByRole("status")).toHaveText("Select and copy the link below.");
  expect(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth)).toBe(false);
  await page.keyboard.press("Escape");
  await expect(sheet).toHaveCount(0);
  await expect(page.locator(".site-header-download")).toBeFocused();
  await expect(page.getByRole("button", { name: "Close navigation" })).toBeInViewport();
  await page.mouse.move(160, 500);
  await page.mouse.wheel(0, 600);
  await page.waitForTimeout(300);
  await expect(page.getByRole("button", { name: "Close navigation" })).toBeInViewport();
  await page.keyboard.press("Escape");
  await expect(page.getByRole("button", { name: "Open navigation" })).toBeFocused();
  await expect(page.locator("body")).not.toHaveCSS("position", "fixed");
  // Start a new gesture over the page. WebKit otherwise keeps the wheel
  // sequence latched to the menu that just stopped being scrollable.
  await page.mouse.move(180, 450);
  await page.mouse.wheel(0, 600);
  await expect.poll(() => page.evaluate(() => scrollY)).toBeGreaterThan(100);
});

test("iPad desktop browsing offers handoff while narrow Mac windows keep the download", async ({ page }) => {
  await page.addInitScript(() => {
    Object.defineProperty(navigator, "userAgent", { value: "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0)" });
    Object.defineProperty(navigator, "platform", { value: "MacIntel" });
    Object.defineProperty(navigator, "maxTouchPoints", { value: 5, configurable: true });
  });
  await page.goto("/");
  await expect(page.locator(".landing-download").first()).toBeVisible();
  await page.addInitScript(() => Object.defineProperty(navigator, "maxTouchPoints", { value: 0, configurable: true }));
  await page.setViewportSize({ width: 390, height: 844 });
  await page.reload();
  await expect(page.getByRole("link", { name: "Download for Mac" }).first()).toHaveAttribute("href", /\.dmg$/);
  await expect(page.getByRole("button", { name: "Get hush for Mac" })).toHaveCount(0);
});
