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

test("LANDING-ENTRY-001 plays the text entrance from the first paint and coordinates the universe's calendar with the prepared scene", async ({ page }, testInfo) => {
  let release!: () => void;
  const gate = new Promise<void>(resolve => { release = resolve; });
  await page.route(/HushScene.*\.js/, async route => { await gate; await route.continue(); });
  // Hold only the fallback clock to exercise a prompt scene on slow CI GPUs.
  // The real three-second choreography runs normally once the scene starts it.
  await page.route(/\/assets\/.*\.css$/, async route => {
    const response = await route.fetch();
    await route.fulfill({ response, body: await response.text() +
      '\n.hush-landing[data-opening="pending"] :is(.hush-core,.orbit-app,.universe-paths,.universe-halo,.universe-texture) { animation-play-state: paused; }' });
  });
  try {
    await page.goto("/", { waitUntil: "domcontentloaded" });
    await expect(page.locator(".site-header")).toHaveCSS("position", "relative");
    // The text runs its own entrance from the first paint while the universe still waits.
    const text = await page.evaluate(() => [".site-header", ".hero-introduction", ".hero-download-area"].map(selector => {
      const timing = document.querySelector(selector)!.getAnimations()[0]?.effect?.getTiming();
      return [timing?.delay, Number(timing?.duration)];
    }));
    expect(text).toEqual([[120, 1050], [0, 900], [1100, 700]]);
    const fade = await page.evaluate(() => {
      const header = document.querySelector<HTMLElement>(".site-header")!;
      const animation = header.getAnimations().find(item => (item as CSSAnimation).animationName === "header-arrive")!;
      const timing = animation.effect!.getTiming();
      const originalTime = animation.currentTime;
      const height = header.offsetHeight, top = header.offsetTop;
      animation.pause();
      animation.currentTime = Number(timing.delay) + Number(timing.duration) * .4;
      const style = getComputedStyle(header);
      const result = { opacity: Number(style.opacity), y: new DOMMatrixReadOnly(style.transform).m42, sameLayout: height === header.offsetHeight && top === header.offsetTop, filter: style.filter };
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
    for (const selector of [".site-header", ".hero-introduction", ".hero-download-area"]) {
      await expect(page.locator(selector)).toHaveCSS("opacity", "1", { timeout: 4000 });
    }
    await expect(page.locator(".hero-actions .landing-download")).toBeVisible();
    await expect(page.locator(".landing-loader")).toHaveCount(0);
    await expect(page.locator(".hush-core")).toHaveCSS("opacity", "0");
    const layout = await page.locator(".hero-introduction").boundingBox();
    release();
    await expect(page.locator(".hush-landing")).toHaveAttribute("data-opening", "playing", { timeout: 15000 });
    const calendar = await page.evaluate(() => [".hush-core", ".orbit-app", ".universe-paths", ".universe-texture", ".universe-halo"].map(selector => {
      const animation = document.querySelector(selector)!.getAnimations()[0];
      if (!animation) throw new Error(`${selector} has no entrance animation`);
      const timing = animation.effect!.getTiming();
      return { selector, delay: timing.delay, duration: Number(timing.duration), start: Number(animation.startTime) };
    }));
    expect(calendar.map(({ delay, duration }) => [delay, duration])).toEqual([
      [100, 650], [1000, 1150], [850, 1500], [0, 2400], [300, 1400],
    ]);
    expect(Math.max(...calendar.map(item => item.start)) - Math.min(...calendar.map(item => item.start))).toBeLessThan(1);
    // The scene starting neither replays nor moves the text.
    expect(await page.evaluate(() => [".site-header", ".hero-introduction", ".hero-download-area"].map(selector =>
      document.querySelector(selector)!.getAnimations().every(item => item.playState === "finished")))).toEqual([true, true, true]);
    expect(await page.locator(".hero-introduction").boundingBox()).toEqual(layout);
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
    await expect(page.locator(".hush-landing")).toHaveAttribute("data-opening", "complete", { timeout: 5000 });
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
    // Navigation, headline and download arrive without JavaScript, well before the
    // universe's 3.8-second fallback.
    await expect(page.locator(".hero-introduction")).toHaveCSS("opacity", "1", { timeout: 2500 });
    await expect(page.locator(".site-header")).toHaveCSS("opacity", "1", { timeout: 2500 });
    await expect(page.locator(".hero-download-area")).toHaveCSS("opacity", "1", { timeout: 2500 });
    await expect(page.locator(".hush-core")).toHaveCSS("opacity", "1", { timeout: 4800 });
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

test("LANDING-ENTRY-006 links every page's own styles in its prerendered head", async ({ page, request }) => {
  for (const path of ["/", "/de", "/verified-messages", "/impressum", "/datenschutz"]) {
    const html = await (await request.get(path)).text();
    const head = html.slice(0, html.indexOf("</head>"));
    const linked = [...head.matchAll(/<link rel="stylesheet"[^>]*href="([^"]+)"/g)].map((match) => match[1]);
    await page.goto(path);
    await page.waitForLoadState("networkidle");
    // A stylesheet the page needs but links only from JavaScript paints the page unstyled first.
    const used = await page.evaluate(() => [...document.styleSheets].flatMap((sheet) => (sheet.href ? [new URL(sheet.href).pathname] : [])));
    expect(used.length, path).toBeGreaterThan(0);
    expect(used.filter((href) => !linked.includes(href)), path).toEqual([]);
  }
});
