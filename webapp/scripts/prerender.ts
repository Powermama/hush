// SPDX-License-Identifier: AGPL-3.0-only
// Copyright 2026 Clemens Kressmann
import { sitePages, siteOrigin, privatePageMetadata } from "../shared/site";
import { renderPageHead } from "../shared/site-head";
import { createHash } from "node:crypto";

// Vite compiles CSS, static assets and environment-specific imports for SSR.
const { render } = await import("../dist-ssr/entry-server.js");
const template = await Bun.file("dist/index.html").text();
const head = template.match(/<head>([\s\S]*?)<\/head>/)?.[1];
if (!head) throw new Error("Missing Vite document head");
const pageHead = (metadata: typeof privatePageMetadata) => head.replace(
  /<!--hush-head-start-->[\s\S]*?<!--hush-head-end-->/,
  () => renderPageHead(metadata),
);
const pages: Record<string, string> = {};
for (const [path, metadata] of Object.entries(sitePages)) {
  const response = await render(`${siteOrigin}${path}`);
  if (!response.ok) throw new Error(`Cannot prerender ${path}: ${response.status}`);
  let html = await response.text();
  if (!html.includes("<h1") || !html.includes("$_TSR")) {
    throw new Error(`Missing page content or hydration data: ${path}`);
  }
  html = html.replace('<html lang="en">', `<html lang="${metadata.language}">`);
  // Preserve React's resource hints alongside Vite's compiled script and CSS.
  html = html.replace("<head>", () => `<head>${pageHead(metadata)}`);
  // Keep the existing script-src 'self' policy. Router hydration is an external,
  // immutable build asset, not an inline-script exemption. Escape embedded NULs
  // before HTML parsing can replace them and corrupt TanStack's match IDs.
  const scripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)];
  for (const [tag, source] of scripts) {
    const code = source!.replaceAll("\u0000", "\\u0000");
    const digest = createHash("sha256").update(code).digest("hex").slice(0, 16);
    const asset = `/assets/route-${digest}.js`;
    await Bun.write(`dist${asset}`, code);
    html = html.replace(tag, `<script src="${asset}"></script>`);
  }
  pages[path] = html;
}
// Kept outside the public static directory. Only explicit server routes serve it.
await Bun.write("dist-pages/pages.json", JSON.stringify(pages));
// The client-only shell serves private proofs and unknown release pages only.
await Bun.write("dist/index.html", template.replace(/<head>[\s\S]*?<\/head>/, () => `<head>${pageHead(privatePageMetadata)}</head>`));
console.info(`Prerendered ${Object.keys(pages).length} public documents. No message proofs were rendered.`);
