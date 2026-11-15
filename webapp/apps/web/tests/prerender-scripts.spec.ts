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
      export async function render(url) {
        // Like the real renderer, unknown addresses answer 404 with the not-found page.
        if (new URL(url).pathname.endsWith("/__not-found")) return new Response('<html lang="en"><head></head><body><h1 id="not-found-title">Not found</h1></body></html>', { status: 404 });
        return new Response(document);
      }
    `);

    for (const [open, close] of [["script", "script"], ["SCRIPT", "SCRIPT"], ["ScRiPt", "sCrIpT"], ["script ", "script data-end='ignored'"], ["script\n", "script\t"]]) {
      await writeFile(join(directory, "dist/index.html"), '<html><head><!--hush-head-start--><!--hush-head-end--></head><body></body></html>');
      // Prerendering preloads the landing scene and each page's own code from the build manifest, then removes it.
      await mkdir(join(directory, "dist/.vite"), { recursive: true });
      const pageModules = ["src/app/App.tsx", "src/landing/GermanLanding.tsx", "src/verified/VerifiedMessagesPage.tsx",
        "src/releases/ReleaseNotesPage.tsx", "src/releases/ReleaseRoute.tsx", "src/legal/LegalPages.tsx"];
      await writeFile(join(directory, "dist/.vite/manifest.json"), JSON.stringify({
        "src/landing/HushScene.ts": { file: "assets/HushScene.js", isDynamicEntry: true, assets: ["assets/studio-lighting.ktx2.gz"] },
        ...Object.fromEntries(pageModules.map((key) => [key, { file: `assets/${key.split("/").at(-1)!.replace(/\.tsx$/, "")}.js`, isDynamicEntry: true }])),
        // The landing's own styles come with a chunk it imports.
        "src/app/App.tsx": { file: "assets/App.js", isDynamicEntry: true, imports: ["_Landing.js"] },
        "_Landing.js": { file: "assets/Landing.js", css: ["assets/Landing.css"] },
      }));
      const document = `<html lang="en"><head></head><body><h1>Prerender fixture</h1><button id="action">Open menu</button><${open}>window.$_TSR = {}; document.querySelector('#action').addEventListener('click', event => { event.currentTarget.textContent = 'Menu opened'; });</${close}></body></html>`;
      await writeFile(join(directory, "dist-ssr/document.html"), document);
      await run("bun", ["scripts/prerender.ts"], { cwd: directory });
      const pages = JSON.parse(await readFile(join(directory, "dist-pages/pages.json"), "utf8"));
      // A page's own styles are linked in its head, so it never paints unstyled.
      expect(pages["/"].slice(0, pages["/"].indexOf("</head>"))).toContain('<link rel="stylesheet" crossorigin href="/assets/Landing.css">');
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
