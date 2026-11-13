import { expect, test } from "@playwright/test";

test("LANDING-VM-003 follows one message through the illustrated story", async ({ page, isMobile }, testInfo) => {
  const errors: string[] = [];
  const externalImages: string[] = [];
  page.on("pageerror", error => errors.push(error.message));
  page.on("request", request => {
    if (request.resourceType() === "image" && new URL(request.url()).origin !== new URL(page.url()).origin) externalImages.push(request.url());
  });
  await page.goto("/verified-messages");
  await expect(page.getByRole("heading", { level: 1, name: "Make your voice more than a post." })).toBeVisible();
  const portrait = page.getByRole("img", { name: /Ameca robot photograph/ });
  await portrait.scrollIntoViewIfNeeded();
  await expect(portrait).toHaveAttribute("data-scene", "ready");
  await expect(page.getByRole("link", { name: "CC BY-SA 4.0" })).toHaveAttribute("href", "https://creativecommons.org/licenses/by-sa/4.0/");
  await page.locator(".vm-opening").screenshot({ path: testInfo.outputPath("verified-opening.png") });

  const story = page.getByRole("region", { name: "Let your words carry their story." });
  await story.getByRole("button", { name: "Record", exact: true }).click();
  // The artwork can overlap the composition, but never its heading or controls.
  const heading = (await story.getByRole("heading", { level: 2 }).boundingBox())!;
  const player = (await story.locator(".message-story-window").boundingBox())!;
  expect(heading.y + heading.height).toBeLessThan(player.y);
  const artwork = story.getByRole("img", { name: /Paul Klee/ });
  await expect.poll(() => artwork.evaluate((el: HTMLImageElement) => el.complete && el.naturalWidth > 0)).toBe(true);
  await expect(artwork).toHaveAttribute("src", /\/assets\/twittering-machine-[\w-]+\.webp$/);
  await expect(page.locator('img[src*="liberty"], img[src*="aristotle"], img[src*="steve-jobs"], img[src*="public-portrait"]')).toHaveCount(0);
  await expect(story.getByText("Listening on your Mac")).toBeVisible();
  await expect(story.locator(".message-record time")).toHaveAttribute("datetime", "2026-11-04T10:42:08Z");
  await story.screenshot({ path: testInfo.outputPath("story-record.png") });

  await story.getByRole("button", { name: "Share", exact: true }).click();
  await expect(story.getByLabel("Illustrative shared message").locator(".message-post-content")).toContainText("Let’s build something that matters, together.");
  await expect(story.locator(".message-post-content").getByRole("link", { name: "- verified by hush" })).toBeVisible();
  await expect(story.getByRole("img", { name: "hushy, the hush mascot" })).toBeVisible();
  await expect(story.getByText("hushy", { exact: true })).toBeVisible();
  await expect(story.getByText("@heyhush", { exact: true })).toBeVisible();
  await expect(story.locator(".message-post-content br")).toHaveCount(0);
  await expect(story.getByText(/Illustrative record and times/)).toHaveCount(0);
  await story.screenshot({ path: testInfo.outputPath("story-share.png") });
  const link = story.getByRole("link", { name: "- verified by hush" });
  await link.focus();
  await page.keyboard.press("Enter");
  const proof = page.getByRole("article", { name: "Illustrative Verified Message" });
  await expect(proof).toBeFocused();
  await expect(proof.getByRole("heading", { name: "Verified hush message" })).toBeVisible();
  await expect(story.getByText("Illustration", { exact: true })).toBeVisible();
  await expect(proof.locator("blockquote")).toHaveText("Let’s build something that matters, together.");
  await expect(proof.locator("li")).toHaveCount(3);
  await expect(proof.locator("time")).toHaveText(["10:42:08 UTC", "10:42:26 UTC", "10:42:27 UTC"]);
  await story.screenshot({ path: testInfo.outputPath("story-verify.png") });
  await expect(proof.getByText("See the recorded edit")).toHaveCount(0);
  await expect(proof.getByText(/No audio attached/)).toBeVisible();
  await expect(story.getByText("About this illustration & your privacy")).toHaveCount(0);
  await expect(page.getByText("Verified Messages are optional.")).toBeVisible();
  if (!isMobile) {
    const download = page.locator(".vm-download");
    await download.scrollIntoViewIfNeeded();
    await page.mouse.move(0, 0);
    const colors = await download.evaluate(el => ({ background: getComputedStyle(el).backgroundColor, text: getComputedStyle(el).color }));
    await download.hover();
    await expect(download).toHaveCSS("background-color", colors.background);
    await expect(download).toHaveCSS("color", colors.text);
  }
  if (isMobile) await expect(page.locator(".vm-download").first()).toBeVisible();
  else await expect(page.getByRole("link", { name: "Download hush", exact: true }).first()).toHaveAttribute("href", "https://updates.behu.sh/downloads/hush-0.1.0-alpha.5-build.14.dmg");
  expect(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth)).toBe(false);
  expect(externalImages).toEqual([]);
  expect(errors).toEqual([]);
});

test("LANDING-VM-004 keeps the story usable without WebGL or motion", async ({ page, browserName }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.addInitScript(() => {
    const original = HTMLCanvasElement.prototype.getContext;
    HTMLCanvasElement.prototype.getContext = function (kind: string, ...args: unknown[]) {
      if (kind === "webgl2" || kind === "webgl") return null;
      return Reflect.apply(original, this, [kind, ...args]);
    } as typeof original;
  });
  await page.goto("/verified-messages");
  await expect(page.getByRole("link", { name: "Skip to content" })).toBeAttached();
  await page.keyboard.press(browserName === "webkit" ? "Alt+Tab" : "Tab");
  await expect(page.getByRole("link", { name: "Skip to content" })).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(page).toHaveURL(/#vm-main$/);
  const portrait = page.getByRole("img", { name: /Ameca robot photograph/ });
  await portrait.scrollIntoViewIfNeeded();
  await expect(portrait).toHaveAttribute("data-scene", "fallback");
  await expect(portrait.locator("canvas")).toHaveCount(0);
  await expect(page.getByRole("article", { name: "Illustrative Verified Message" })).toBeVisible();
  await expect(page.getByRole("button", { name: /(?:Play|Pause|Replay) illustration/ })).toHaveCount(0);
  await page.getByRole("button", { name: "Record", exact: true }).click();
  await expect(page.getByText("Listening on your Mac")).toBeVisible();
  await expect(page.locator(".message-story-scene")).toHaveCSS("animation-name", "none");
  await page.getByRole("button", { name: "Share", exact: true }).click();
  await page.getByRole("link", { name: "- verified by hush" }).click();
  const proof = page.getByRole("article", { name: "Illustrative Verified Message" });
  await expect(proof).toBeFocused();
  await expect(proof.locator("li")).toHaveCount(3);
});

test("LANDING-VM-005 plays once, pauses away from view and supports replay", async ({ page }) => {
  await page.goto("/verified-messages");
  const player = page.locator(".message-story-player");
  const window = page.locator(".message-story-window");
  await window.scrollIntoViewIfNeeded();
  await expect(player).toHaveAttribute("data-running", "true");
  await page.getByRole("button", { name: "Pause illustration" }).click();
  await expect(player).toHaveAttribute("data-running", "false");
  await expect(page.getByText("Listening on your Mac")).toBeVisible();
  await page.getByRole("button", { name: "Play illustration" }).click();
  await expect(page.getByLabel("Illustrative shared message")).toBeVisible({ timeout: 6500 });
  await page.evaluate(() => scrollTo(0, 0));
  await expect(player).toHaveAttribute("data-running", "false");
  await page.waitForTimeout(1500); // Prove the paused offscreen scene does not advance.
  await expect(player).toHaveAttribute("data-phase", "share");
  await window.scrollIntoViewIfNeeded();
  await expect(player).toHaveAttribute("data-running", "true");
  await expect(page.getByRole("article", { name: "Illustrative Verified Message" })).toBeVisible({ timeout: 6500 });
  await expect(page.getByRole("button", { name: "Replay illustration" })).toBeVisible({ timeout: 6500 });
  await expect(player).toHaveAttribute("data-running", "false");
  await page.getByRole("button", { name: "Replay illustration" }).click();
  await expect(page.getByText("Listening on your Mac")).toBeVisible();
  await page.getByRole("button", { name: "Verify", exact: true }).click();
  await expect(player).toHaveAttribute("data-running", "false");
  await expect(page.getByRole("button", { name: "Play illustration" })).toBeVisible();
});
