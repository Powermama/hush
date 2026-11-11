import { expect, test } from "@playwright/test";

test("flower stays bounded during scrolling and resizing", async ({ page }) => {
  // Four real viewport changes render through software WebGL on hosted Linux.
  test.slow();
  const errors: string[] = [];
  page.on("pageerror", error => errors.push(error.message));
  await page.goto("/");
  const flower = page.getByRole("img", { name: /sculptural pearl and lilac rose/ });
  for (const width of [390, 1440, 820, 390]) {
    await page.setViewportSize({ width, height: 900 });
    await flower.scrollIntoViewIfNeeded();
    await expect(flower).toHaveAttribute("data-scene", /ready|fallback/, { timeout: 10000 });
    const initial = (await flower.boundingBox())!;
    await page.mouse.wheel(0, 280);
    await page.mouse.wheel(0, -280);
    await expect.poll(async () => Math.round((await flower.boundingBox())!.height)).toBe(Math.round(initial.height));
    expect(initial.height).toBeLessThan(1200);
    for (const canvas of await flower.locator("canvas").all()) {
      const dimensions = await canvas.evaluate((el: HTMLCanvasElement) => ({ width: el.width, height: el.height, position: getComputedStyle(el).position }));
      expect(dimensions.width).toBeLessThanOrEqual(1500);
      expect(dimensions.height).toBeLessThanOrEqual(1800);
      expect(dimensions.position).toBe("absolute");
    }
    expect(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth)).toBe(false);
  }
  expect(errors).toEqual([]);
});

test("flower keeps its static artwork without WebGL", async ({ page }) => {
  await page.addInitScript(() => {
    const original = HTMLCanvasElement.prototype.getContext;
    HTMLCanvasElement.prototype.getContext = function (kind: string, ...args: unknown[]) {
      if (kind === "webgl2" || kind === "webgl") return null;
      return Reflect.apply(original, this, [kind, ...args]);
    } as typeof original;
  });
  await page.goto("/");
  const flower = page.locator(".freedom-bloom");
  await flower.scrollIntoViewIfNeeded();
  await expect(flower).toHaveAttribute("data-scene", "fallback");
  await expect(flower.locator(".bloom-fallback")).toBeVisible();
  await expect(flower.locator("canvas")).toHaveCount(0);
  await expect(page.getByRole("link", { name: "Explore the source" })).toBeVisible();
});

test("flower stops drawing when idle and offscreen", async ({ page }) => {
  await page.addInitScript(() => {
    for (const type of [WebGLRenderingContext, WebGL2RenderingContext]) {
      const draw = type.prototype.drawElements;
      type.prototype.drawElements = function (...args: Parameters<typeof draw>) {
        if (this.canvas instanceof HTMLCanvasElement && this.canvas.closest(".freedom-bloom")) {
          const canvas = this.canvas;
          canvas.dataset.drawCount = String(Number(canvas.dataset.drawCount ?? 0) + 1);
        }
        return Reflect.apply(draw, this, args);
      };
    }
  });
  await page.goto("/");
  const flower = page.locator(".freedom-bloom");
  await flower.scrollIntoViewIfNeeded();
  await expect(flower).toHaveAttribute("data-scene", /ready|fallback/, { timeout: 10000 });
  test.skip(await flower.getAttribute("data-scene") === "fallback", "WebGL unavailable; static artwork covered separately");
  const canvas = flower.locator("canvas");
  await expect(canvas).toHaveAttribute("data-draw-count", /[1-9]/);
  // Allow the finite pointer easing to settle, then measure real GPU draw calls.
  await page.mouse.move(0, 0);
  await expect.poll(async () => {
    const before = await canvas.getAttribute("data-draw-count");
    await page.waitForTimeout(180);
    return before === await canvas.getAttribute("data-draw-count");
  }, { timeout: 5000 }).toBe(true);
  const idle = await canvas.getAttribute("data-draw-count");
  await page.waitForTimeout(350);
  await expect(canvas).toHaveAttribute("data-draw-count", idle!);
  await page.getByRole("heading", { level: 1 }).scrollIntoViewIfNeeded();
  await page.waitForTimeout(100);
  const offscreen = await canvas.getAttribute("data-draw-count");
  await page.mouse.move(100, 100);
  await page.waitForTimeout(350);
  await expect(canvas).toHaveAttribute("data-draw-count", offscreen!);
});

test("rose opens with native scroll and closes when scrolling back", async ({ page }, testInfo) => {
  // Read the actual rendered silhouette, not just the animation's progress value.
  // Preserve the drawing buffer only in this test so pixel reads are deterministic.
  await page.addInitScript(() => {
    const original = HTMLCanvasElement.prototype.getContext;
    HTMLCanvasElement.prototype.getContext = function (kind: string, options: object = {}) {
      return Reflect.apply(original, this, [kind, kind === "webgl2" ? { ...options, preserveDrawingBuffer: true } : options]);
    } as typeof original;
  });
  await page.goto("/");
  await page.mouse.move(0, 0);
  const rose = page.locator(".freedom-bloom");
  await rose.evaluate(el => {
    const bounds = el.getBoundingClientRect();
    window.scrollTo({ top: scrollY + bounds.top + bounds.height * .28 - innerHeight * .78, behavior: "instant" });
  });
  await expect(rose).toHaveAttribute("data-scene", /ready|fallback/, { timeout: 15000 });
  test.skip(await rose.getAttribute("data-scene") === "fallback", "WebGL unavailable; static artwork covered separately");
  const progress = async () => Number(await rose.getAttribute("data-bloom"));
  const bloomWidth = () => rose.locator("canvas").evaluate((canvas: HTMLCanvasElement) => {
    const gl = canvas.getContext("webgl2")!;
    const height = Math.floor(canvas.height * .5);
    const pixels = new Uint8Array(canvas.width * height * 4);
    gl.readPixels(0, canvas.height - height, canvas.width, height, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
    let left = canvas.width, right = 0;
    for (let y = 0; y < height; y++) for (let x = 0; x < canvas.width; x++) {
      if (pixels[(y * canvas.width + x) * 4 + 3] > 32) { left = Math.min(left, x); right = Math.max(right, x); }
    }
    return (right - left) / canvas.width;
  });
  await expect.poll(progress).toBeLessThan(.01);
  const closedWidth = await bloomWidth();
  expect(closedWidth).toBeGreaterThan(.1);
  await page.waitForTimeout(500);
  await expect.poll(progress).toBeLessThan(.01); // Entering view alone never plays it.
  await page.screenshot({ path: testInfo.outputPath("rose-closed.png") });
  const viewportHeight = page.viewportSize()!.height;
  await page.mouse.wheel(0, Math.round(viewportHeight * .3));
  await expect.poll(progress).toBeGreaterThan(.47);
  await expect.poll(progress).toBeLessThan(.53);
  const halfWidth = await bloomWidth();
  expect(halfWidth).toBeGreaterThan(closedWidth * 1.15);
  await page.screenshot({ path: testInfo.outputPath("rose-half-open.png") });
  await page.mouse.wheel(0, Math.round(viewportHeight * .35));
  await expect.poll(progress).toBeGreaterThan(.98);
  expect(await bloomWidth()).toBeGreaterThan(halfWidth * 1.15);
  await page.screenshot({ path: testInfo.outputPath("rose-open.png") });
  await page.mouse.wheel(0, -Math.round(viewportHeight * .65));
  await expect.poll(progress).toBeLessThan(.01);
  expect(await bloomWidth()).toBeCloseTo(closedWidth, 1);
});

test("rose stays open with reduced motion and survives a missing model", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/");
  const rose = page.locator(".freedom-bloom");
  await rose.scrollIntoViewIfNeeded();
  await expect(rose).toHaveAttribute("data-scene", /ready|fallback/, { timeout: 15000 });
  if (await rose.getAttribute("data-scene") === "ready") {
    await expect(rose).toHaveAttribute("data-bloom", "1.000");
    await page.mouse.wheel(0, -150);
    await expect(rose).toHaveAttribute("data-bloom", "1.000");
  }
  await page.route(/rose-.*\.glb$/, route => route.abort());
  await page.reload();
  await rose.scrollIntoViewIfNeeded();
  await expect(rose).toHaveAttribute("data-scene", "fallback");
  await expect(rose.locator(".bloom-fallback")).toBeVisible();
  await expect(page.getByRole("link", { name: "Explore the source" })).toBeVisible();
});
