// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { expect, test } from "bun:test";
import { externalizeScripts } from "./externalize-scripts";

test("preserves inert markup, attributed scripts, order and exact hydration data", () => {
  const inert = '<!--<script>comment()</script>--><template><script>template()</script></template>' +
    '<noscript><script>noscript()</script></noscript>' +
    '<script type="application/ld+json">{"name":"hush"}</script>' +
    '<script type="module" src="/entry.js"></script>';
  const first = 'window.$_TSR = "\u0000/&<";';
  const second = "window.order = 2;";
  const result = externalizeScripts('<!doctype html><html><body>' + inert +
    `<ScRiPt >${first}</sCrIpT data-ignored="yes"><script\n>${second}</script\t>` +
    '</body></html>');
  expect(result.html).toContain(inert);
  expect(result.assets.map(asset => asset.code)).toEqual([first.replaceAll("\u0000", "\\u0000"), second]);
  expect(result.html.indexOf(result.assets[0]!.path)).toBeLessThan(result.html.indexOf(result.assets[1]!.path));
  expect(result.html).not.toContain("data-ignored");
});

test("deduplicates asset bytes without losing repeated script execution or changing comments", () => {
  const script = "<script>window.count++;</script>";
  const result = externalizeScripts(`<!--${script}-->${script}${script}`);
  expect(result.assets).toHaveLength(1);
  expect(result.html).toStartWith(`<!--${script}-->`);
  expect(result.html.split(`src="${result.assets[0]!.path}"`)).toHaveLength(3);
  expect(externalizeScripts(script).assets).toEqual(result.assets);
});

test("rejects an incomplete SSR script instead of emitting a broken page", () => {
  expect(() => externalizeScripts("<script>window.incomplete = true;")).toThrow("unclosed SSR script");
});
