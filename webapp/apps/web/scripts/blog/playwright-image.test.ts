// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { expect, test } from "bun:test";

// The CMS build renders covers with the Chromium of the official Playwright
// image; @playwright/test only launches the browser revision of its own version.
test("the Dockerfile's Playwright image matches @playwright/test", async () => {
  const dockerfile = await Bun.file(new URL("../../Dockerfile", import.meta.url)).text();
  const manifest = await Bun.file(new URL("../../package.json", import.meta.url)).json() as { devDependencies?: Record<string, string>; dependencies?: Record<string, string> };
  const version = manifest.devDependencies?.["@playwright/test"] ?? manifest.dependencies?.["@playwright/test"];
  const image = /mcr\.microsoft\.com\/playwright:v([0-9.]+)-/.exec(dockerfile)?.[1];
  expect(version).toMatch(/^\d+\.\d+\.\d+$/);
  expect(image).toBe(version);
});
