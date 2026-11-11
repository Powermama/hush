import { expect, test } from "@playwright/test";

test("keeps navigation and static artwork usable when studio lighting fails", async ({ page }) => {
  const errors: string[] = [];
  page.on("pageerror", error => errors.push(error.message));
  await page.route(/studio-environment.*\.gz$/, route => route.abort());
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

test("LANDING-ENTRY-001 starts blank and reveals the header with the hero", async ({ page }, testInfo) => {
  let release!: () => void;
  const gate = new Promise<void>(resolve => { release = resolve; });
  const sceneRequest = page.waitForRequest(/HushScene.*\.js/);
  await page.route(/HushScene.*\.js/, async route => { await gate; await route.continue(); });
  try {
    await page.goto("/", { waitUntil: "domcontentloaded" });
    await sceneRequest;
    const initial = await page.evaluate(() => Object.fromEntries([
      ".site-header", ".hero-introduction", ".core-fallback", ".universe-halo", ".universe-paths", ".universe-texture", ".hero-download-area",
    ].map(selector => [selector, getComputedStyle(document.querySelector(selector)!).opacity])));
    expect(initial).toEqual({
      ".site-header": "0", ".hero-introduction": "0", ".core-fallback": "0", ".universe-halo": "0", ".universe-paths": "0", ".universe-texture": "0", ".hero-download-area": "0",
    });
    // Sample as the CSS animation is created, not after slow screenshots or
    // cross-process assertions have already consumed its one-second lifetime.
    await page.evaluate(() => {
      const root = document.querySelector(".hush-landing")!;
      const header = document.querySelector<HTMLElement>(".site-header")!;
      const observer = new MutationObserver(() => {
        if ((root as HTMLElement).dataset.opening !== "playing") return;
        const animation = header.getAnimations().find(item => (item as CSSAnimation).animationName === "header-arrive");
        if (!animation?.effect) return;
        const timing = animation.effect.getTiming();
        const height = header.offsetHeight, top = header.offsetTop;
        animation.pause();
        animation.currentTime = timing.delay + Number(timing.duration) * .4;
        const style = getComputedStyle(header);
        header.dataset.testFade = JSON.stringify({
          opacity: Number(style.opacity), y: new DOMMatrixReadOnly(style.transform).m42,
          sameLayout: height === header.offsetHeight && top === header.offsetTop,
          filter: style.filter,
        });
        animation.play(); observer.disconnect();
      });
      observer.observe(root, { attributes: true, attributeFilter: ["data-opening"] });
    });
  } finally { release(); }
  await expect(page.locator(".site-header")).toHaveAttribute("data-test-fade", /opacity/);
  const fade = JSON.parse((await page.locator(".site-header").getAttribute("data-test-fade"))!);
  expect(fade.opacity).toBeGreaterThan(0);
  expect(fade.opacity).toBeLessThan(1);
  expect(fade.y).toBeGreaterThan(-14);
  expect(fade.y).toBeLessThan(0);
  expect(fade.sameLayout).toBe(true);
  expect(fade.filter).toBe("none");
  await expect(page.locator(".hush-landing")).toHaveAttribute("data-opening", "complete", { timeout: 8000 });
  await expect(page.locator(".site-header")).toHaveCSS("opacity", "1");
  await expect(page.locator(".hero-introduction")).toHaveCSS("opacity", "1");
  await expect(page.locator(".hero-introduction")).toHaveCSS("filter", "none");
  await expect(page.locator(".hush-core canvas")).toHaveCSS("opacity", "1");
  await page.screenshot({ path: testInfo.outputPath("entrance-complete.png") });
});

test("LANDING-ENTRY-002 recovers a slow scene without replaying the entrance", async ({ page }) => {
  let release!: () => void;
  const gate = new Promise<void>(resolve => { release = resolve; });
  await page.route(/HushScene.*\.js/, async route => { await gate; await route.continue(); });
  try {
    await page.goto("/", { waitUntil: "domcontentloaded" });
    await expect(page.locator(".hush-landing")).toHaveAttribute("data-opening", "complete", { timeout: 4000 });
    await expect(page.locator(".site-header")).toHaveCSS("opacity", "1");
    await expect(page.locator(".core-fallback")).toHaveCSS("opacity", "1");
    await expect(page.locator(".hero-actions .landing-download")).toBeVisible();
  } finally { release(); }
  // The four-second usable-page deadline above stays strict. Compiling the
  // deferred WebGL scene on a software renderer has a separate readiness budget.
  await expect(page.locator(".hush-core")).toHaveAttribute("data-scene", "ready", { timeout: 15000 });
  await expect(page.locator(".hush-landing")).toHaveAttribute("data-opening", "complete");
  await expect(page.locator(".site-header")).toHaveCSS("animation-name", "none");
});
