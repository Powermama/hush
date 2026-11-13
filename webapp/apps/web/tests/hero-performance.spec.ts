// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { expect, test, type Page } from "@playwright/test";

type Preparation = { release: boolean; polls: number; earlyDraws: number; deletedPrograms: number };
const preparation = (page: Page) => page.evaluate(() =>
  (window as unknown as { shaderPreparation: Preparation }).shaderPreparation);
const releaseShaders = (page: Page) => page.evaluate(() => {
  (window as unknown as { shaderPreparation: Preparation }).shaderPreparation.release = true;
});

async function holdShaders(page: Page) {
  // Model pending compilation independently of the machine's actual speed.
  await page.addInitScript(() => {
    const state = { release: false, polls: 0, earlyDraws: 0, deletedPrograms: 0 };
    Object.assign(window, { shaderPreparation: state });
    const prototype = WebGL2RenderingContext.prototype;
    const extension = prototype.getExtension;
    const parameter = prototype.getProgramParameter;
    prototype.getExtension = function (name: string) {
      const actual = extension.call(this, name);
      return name === "KHR_parallel_shader_compile"
        ? actual ?? { COMPLETION_STATUS_KHR: 0x91b1 }
        : actual;
    };
    prototype.getProgramParameter = function (program: WebGLProgram, name: number) {
      if (name === 0x91b1) {
        state.polls++;
        if (!state.release) return false;
        if (!extension.call(this, "KHR_parallel_shader_compile")) return true;
      }
      return parameter.call(this, program, name);
    };
    const draw = prototype.drawArrays;
    prototype.drawArrays = function (...args: Parameters<typeof draw>) {
      if (!state.release) state.earlyDraws++;
      return draw.apply(this, args);
    };
    const remove = prototype.deleteProgram;
    prototype.deleteProgram = function (...args: Parameters<typeof remove>) {
      state.deletedPrograms++;
      return remove.apply(this, args);
    };
  });
}

test("LANDING-ENTRY-006 keeps content usable while hero shaders prepare", async ({ page }) => {
  await holdShaders(page);
  await page.goto("/");
  await expect.poll(async () => (await preparation(page)).polls).toBeGreaterThan(0);
  await expect(page.locator(".hush-landing")).toHaveAttribute("data-opening", "complete");
  await expect(page.locator(".hero-introduction")).toHaveCSS("opacity", "1");
  await expect(page.locator(".core-fallback")).toHaveCSS("opacity", "1");
  expect((await preparation(page)).earlyDraws).toBe(0);
  await releaseShaders(page);
  await expect(page.locator(".hush-core")).toHaveAttribute("data-scene", "ready", { timeout: 15000 });
  await expect(page.locator(".site-header")).toHaveCSS("animation-name", "none");
});

test("LANDING-ENTRY-006 releases preparing graphics when navigating away", async ({ page }) => {
  const errors: string[] = [];
  page.on("pageerror", error => errors.push(error.message));
  await holdShaders(page);
  await page.goto("/");
  await expect.poll(async () => (await preparation(page)).polls).toBeGreaterThan(0);
  // Exercise a client-side route unmount. Plain anchor navigation replaces the
  // entire document and its counters, so it cannot verify explicit disposal.
  await page.evaluate(() => {
    history.pushState(null, "", "/verified-messages");
    dispatchEvent(new PopStateEvent("popstate"));
  });
  await expect(page).toHaveURL(/\/verified-messages$/);
  await expect.poll(async () => (await preparation(page)).deletedPrograms).toBeGreaterThan(0);
  await releaseShaders(page);
  await expect(page.locator(".hush-core")).toHaveCount(0);
  await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
  expect(errors).toEqual([]);
});

test("LANDING-ENTRY-006 supports renderers without parallel shader compilation", async ({ page }) => {
  await page.addInitScript(() => {
    const original = WebGL2RenderingContext.prototype.getExtension;
    WebGL2RenderingContext.prototype.getExtension = function (name: string) {
      return name === "KHR_parallel_shader_compile" ? null : original.call(this, name);
    };
  });
  await page.goto("/");
  await expect(page.locator(".hush-core")).toHaveAttribute("data-scene", "ready", { timeout: 15000 });
  await expect(page.locator(".hero-download-area")).toBeVisible();
});

test("LANDING-ENTRY-006 stops hero draws at rest, offscreen and while hidden", async ({ page }, testInfo) => {
  await page.addInitScript(() => {
    const original = WebGL2RenderingContext.prototype.drawArrays;
    WebGL2RenderingContext.prototype.drawArrays = function (...args: Parameters<typeof original>) {
      if (this.canvas instanceof HTMLCanvasElement && this.canvas.closest(".hush-core")) {
        this.canvas.dataset.drawCount = String(Number(this.canvas.dataset.drawCount ?? 0) + 1);
      }
      return original.apply(this, args);
    };
  });
  await page.goto("/");
  const hero = page.locator(".hush-core");
  const canvas = hero.locator("canvas");
  await expect(hero).toHaveAttribute("data-scene", "ready", { timeout: 15000 });
  await page.mouse.move(0, 0);
  await expect(canvas).toHaveAttribute("data-draw-count", /[1-9]/);
  await expect.poll(async () => {
    const count = await canvas.getAttribute("data-draw-count");
    await page.waitForTimeout(200);
    return count === await canvas.getAttribute("data-draw-count");
  }, { timeout: 8000 }).toBe(true);
  const idle = await canvas.getAttribute("data-draw-count");
  await page.waitForTimeout(5000);
  await expect(canvas).toHaveAttribute("data-draw-count", idle!);
  await page.screenshot({ path: testInfo.outputPath("hero-settled.png") });
  const size = await canvas.evaluate(element => ({
    width: (element as HTMLCanvasElement).width, cssWidth: element.getBoundingClientRect().width,
  }));
  expect(size.width).toBeLessThanOrEqual(Math.ceil(size.cssWidth * 1.5));

  // Deterministic visibility lifecycle coverage. Native tab suspension is an
  // additional physical-browser check, not represented by this injected event.
  await page.evaluate(() => {
    Object.defineProperty(document, "hidden", { configurable: true, get: () => true });
    document.dispatchEvent(new Event("visibilitychange"));
  });
  await hero.dispatchEvent("pointermove", { pointerType: "mouse", clientX: 100, clientY: 100 });
  await page.waitForTimeout(300);
  await expect(canvas).toHaveAttribute("data-draw-count", idle!);
  await page.evaluate(() => {
    delete (document as unknown as { hidden?: boolean }).hidden;
    document.dispatchEvent(new Event("visibilitychange"));
  });
  await expect.poll(async () => Number(await canvas.getAttribute("data-draw-count"))).toBeGreaterThan(Number(idle));
  await page.locator("footer").scrollIntoViewIfNeeded();
  await expect(hero).not.toBeInViewport();
  await page.waitForTimeout(200);
  const offscreen = await canvas.getAttribute("data-draw-count");
  await hero.dispatchEvent("pointermove", { pointerType: "mouse", clientX: 200, clientY: 200 });
  await page.waitForTimeout(500);
  await expect(canvas).toHaveAttribute("data-draw-count", offscreen!);
});
