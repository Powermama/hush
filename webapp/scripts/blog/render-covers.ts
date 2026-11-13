// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Renders 1200x630 social previews (PNG) from cover-template.html. Covers are
// committed; this only runs for covers whose files are missing.
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import sharp from "sharp";
import { chromium } from "@playwright/test";
import { coverTemplatePath, type BlogCoverPlan } from "./build-blog";

const escapeHTML = (value: string) => value.replaceAll("&", "&amp;").replaceAll("<", "&lt;")
  .replaceAll(">", "&gt;").replaceAll('"', "&quot;");

export async function renderCovers(covers: BlogCoverPlan[], publicDir = "public") {
  if (!covers.length) return;
  const template = await readFile(coverTemplatePath, "utf8");
  const browser = await chromium.launch();
  try {
    for (const cover of covers) {
      const values: Record<string, string> = {
        LANG: cover.lang, TITLE: cover.title,
        LISTENING: cover.lang === "de" ? "Hört zu" : "Listening",
      };
      const html = template.replace(/\{\{(\w+)\}\}/g, (_, key: string) => {
        if (!(key in values)) throw new Error(`Unknown cover placeholder: ${key}`);
        return escapeHTML(values[key]!);
      });
      const page = await browser.newPage({ viewport: { width: 1200, height: 630 }, deviceScaleFactor: 1 });
      try {
        // The composition is self-contained and must not load remote resources.
        await page.route("**/*", (route) => route.abort());
        await page.setContent(html);
        await page.waitForSelector("body[data-ready]");
        await page.evaluate(() => document.fonts.ready);
        if (await page.locator("h1").textContent() !== cover.title) throw new Error("Cover title did not render correctly");
        const png = await page.screenshot({ type: "png" });
        await mkdir(dirname(`${publicDir}${cover.path}`), { recursive: true });
        await writeFile(`${publicDir}${cover.path}`, await sharp(png).png({ compressionLevel: 9 }).toBuffer());
      } finally {
        await page.close();
      }
    }
  } finally {
    await browser.close();
  }
}
