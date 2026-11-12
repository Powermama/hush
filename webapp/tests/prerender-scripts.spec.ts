// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { execFile } from "node:child_process";
import { cp, mkdir, mkdtemp, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { promisify } from "node:util";
import { expect, test } from "@playwright/test";

const run = promisify(execFile);

test("LANDING-ENTRY-005 preserves interactive scripts under CSP regardless of HTML tag case", async ({ page, baseURL }) => {
  const directory = await mkdtemp(join(tmpdir(), "hush-prerender-case-"));
  try {
    await mkdir(join(directory, "scripts"));
    await mkdir(join(directory, "dist"));
    await mkdir(join(directory, "dist-ssr"));
    await cp("scripts/prerender.ts", join(directory, "scripts/prerender.ts"));
    await cp("scripts/prerender", join(directory, "scripts/prerender"), { recursive: true });
    await symlink(resolve("node_modules"), join(directory, "node_modules"), "dir");
    await cp("shared", join(directory, "shared"), { recursive: true });
    // Keep HTML as data. The fixture module never constructs executable source
    // from the document being tested.
    await writeFile(join(directory, "dist-ssr/entry-server.js"), `
      const document = await Bun.file(new URL("./document.html", import.meta.url)).text();
      export async function render() { return new Response(document); }
    `);

    for (const [open, close] of [["script", "script"], ["SCRIPT", "SCRIPT"], ["ScRiPt", "sCrIpT"], ["script ", "script data-end='ignored'"], ["script\n", "script\t"]]) {
      await writeFile(join(directory, "dist/index.html"), '<html><head><!--hush-head-start--><!--hush-head-end--></head><body></body></html>');
      const document = `<html lang="en"><head></head><body><h1>Prerender fixture</h1><button id="action">Open menu</button><${open}>window.$_TSR = {}; document.querySelector('#action').addEventListener('click', event => { event.currentTarget.textContent = 'Menu opened'; });</${close}></body></html>`;
      await writeFile(join(directory, "dist-ssr/document.html"), document);
      await run("bun", ["scripts/prerender.ts"], { cwd: directory });
      const pages = JSON.parse(await readFile(join(directory, "dist-pages/pages.json"), "utf8"));
      await page.route("**/__prerender-test/", route => route.fulfill({
        contentType: "text/html", body: pages["/"],
        headers: { "Content-Security-Policy": "default-src 'none'; script-src 'self'" },
      }));
      await page.route("**/assets/route-*.js", async route => {
        const path = new URL(route.request().url()).pathname;
        await route.fulfill({ contentType: "text/javascript", body: await readFile(join(directory, "dist", path)) });
      });
      await page.goto(`${baseURL}/__prerender-test/`);
      await page.getByRole("button", { name: "Open menu" }).click();
      await expect(page.getByRole("button", { name: "Menu opened" })).toBeVisible();
      await expect(page.locator('script:not([src]):not([type="application/ld+json"])')).toHaveCount(0);
      await page.unrouteAll({ behavior: "wait" });
    }
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
