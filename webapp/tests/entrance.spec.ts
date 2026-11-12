import { expect, test } from "@playwright/test";

test("keeps navigation and static artwork usable when studio lighting fails", async ({ page }) => {
  const errors: string[] = [];
  page.on("pageerror", error => errors.push(error.message));
  await page.route(/studio-lighting.*\.gz$/, route => route.abort());
  await page.goto("/");
  await expect(page.locator(".hush-core")).toHaveAttribute("data-scene", "fallback");
  await expect(page.locator(".site-header")).toHaveCSS("opacity", "1");
  await expect(page.locator(".core-fallback")).toHaveCSS("opacity", "1");
  await expect(page.locator(".hero-actions .landing-download")).toBeVisible();
  const rose = page.locator(".freedom-bloom");
  await rose.scrollIntoViewIfNeeded();
  await expect(rose).toHaveAttribute("data-scene", "fallback");
  await expect(rose.locator(".bloom-fallback")).toBeVisible();
  expect(errors).toEqual([]);
});

test("LANDING-ENTRY-001 fades the header from first paint without waiting for the scene", async ({ page }, testInfo) => {
  let release!: () => void;
  const gate = new Promise<void>(resolve => { release = resolve; });
  await page.route(/\/assets\/.*\.js(?:\?.*)?$/, async route => { await gate; await route.continue(); });
  try {
    await page.goto("/", { waitUntil: "commit" });
    await expect(page.locator(".site-header")).toHaveCSS("position", "relative");
    const fade = await page.evaluate(() => {
      const header = document.querySelector<HTMLElement>(".site-header")!;
      const animation = header.getAnimations().find(item => (item as CSSAnimation).animationName === "header-arrive")!;
      const timing = animation.effect!.getTiming();
      const originalTime = animation.currentTime;
      const height = header.offsetHeight, top = header.offsetTop;
      animation.pause();
      animation.currentTime = timing.delay + Number(timing.duration) * .4;
      const style = getComputedStyle(header);
      const result = {
        opacity: Number(style.opacity), y: new DOMMatrixReadOnly(style.transform).m42,
        sameLayout: height === header.offsetHeight && top === header.offsetTop,
        filter: style.filter,
      };
      animation.currentTime = originalTime;
      animation.play();
      return result;
    });
    expect(fade.opacity).toBeGreaterThan(0);
    expect(fade.opacity).toBeLessThan(1);
    expect(fade.y).toBeGreaterThan(-14);
    expect(fade.y).toBeLessThan(0);
    expect(fade.sameLayout).toBe(true);
    expect(fade.filter).toBe("none");
  } finally { release(); }
  await expect(page.locator(".hush-landing")).toHaveAttribute("data-opening", "complete");
  await expect(page.locator(".site-header")).toHaveCSS("opacity", "1");
  await expect(page.locator(".hero-introduction")).toHaveCSS("opacity", "1");
  await expect(page.locator(".hero-introduction")).toHaveCSS("filter", "none");
  await expect(page.locator(".hush-core canvas")).toHaveCSS("opacity", "1", { timeout: 15000 });
  await page.screenshot({ path: testInfo.outputPath("entrance-complete.png") });
});

test("LANDING-ENTRY-002 shows content before a slow scene without replaying the entrance", async ({ page }) => {
  let release!: () => void;
  const gate = new Promise<void>(resolve => { release = resolve; });
  await page.route(/HushScene.*\.js/, async route => { await gate; await route.continue(); });
  try {
    await page.goto("/", { waitUntil: "domcontentloaded" });
    await expect(page.locator(".hush-landing")).toHaveAttribute("data-opening", "complete", { timeout: 2500 });
    await expect(page.locator(".site-header")).toHaveCSS("opacity", "1");
    await expect(page.locator(".core-fallback")).toHaveCSS("opacity", "1");
    await expect(page.locator(".hero-actions .landing-download")).toBeVisible();
  } finally { release(); }
  // The usable-page deadline above is independent of scene readiness. Compiling the
  // deferred WebGL scene on a software renderer has a separate readiness budget.
  await expect(page.locator(".hush-core")).toHaveAttribute("data-scene", "ready", { timeout: 15000 });
  await expect(page.locator(".hush-landing")).toHaveAttribute("data-opening", "complete");
  await expect(page.locator(".site-header")).toHaveCSS("animation-name", "none");
});

test("LANDING-ENTRY-003 reveals the prerendered page while application JavaScript is delayed", async ({ page }) => {
  let release!: () => void;
  const gate = new Promise<void>(resolve => { release = resolve; });
  await page.route(/\/assets\/.*\.js(?:\?.*)?$/, async route => { await gate; await route.continue(); });
  try {
    await page.goto("/", { waitUntil: "commit" });
    // The real production CSS must arrive, but neither hydration nor WebGL can run.
    await expect(page.locator(".site-header")).toHaveCSS("position", "relative");
    await expect(page.locator(".hero-introduction")).toHaveCSS("opacity", "1", { timeout: 1800 });
    await expect(page.locator(".site-header")).toHaveCSS("opacity", "1");
    await expect(page.locator(".hero-download-area")).toHaveCSS("opacity", "1");
    await expect(page.locator(".core-fallback")).toHaveCSS("opacity", "1");
    await expect(page.locator(".site-header a[href='/verified-messages']").first()).toHaveAttribute("href", "/verified-messages");
    await expect(page.locator(".hush-core canvas")).toHaveCount(0);
  } finally { release(); }
  await expect(page.locator(".hush-landing")).toHaveAttribute("data-opening", "complete");
  await expect(page.locator(".hero-introduction")).toHaveCSS("opacity", "1");
});

test("LANDING-ENTRY-004 keeps the public page readable when application JavaScript fails", async ({ page }) => {
  await page.route(/\/assets\/.*\.js(?:\?.*)?$/, route => route.abort());
  await page.goto("/");
  await expect(page.locator(".hero-introduction")).toHaveCSS("opacity", "1");
  await expect(page.locator(".site-header")).toHaveCSS("opacity", "1");
  await expect(page.locator(".hero-download-area")).toHaveCSS("opacity", "1");
  await expect(page.locator(".core-fallback")).toHaveCSS("opacity", "1");
  await expect(page.locator(".hush-core canvas")).toHaveCount(0);
  await page.locator("footer a[href='/verified-messages']").click();
  await expect(page).toHaveURL(/\/verified-messages$/);
  await expect(page.locator("h1")).toBeVisible();
});
