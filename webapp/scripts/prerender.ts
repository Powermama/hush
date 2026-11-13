// SPDX-License-Identifier: AGPL-3.0-only
// Copyright 2026 Clemens Kressmann
import { landingPaths, sitePages, siteOrigin, privatePageMetadata } from "../shared/site";
import { renderPageHead } from "../shared/site-head";
import { rm } from "node:fs/promises";
import { externalizeScripts } from "./prerender/externalize-scripts";

// Vite compiles CSS, static assets and environment-specific imports for SSR.
const { render } = await import("../dist-ssr/entry-server.js");
const template = await Bun.file("dist/index.html").text();
const head = template.match(/<head>([\s\S]*?)<\/head>/)?.[1];
if (!head) throw new Error("Missing Vite document head");
const pageHead = (metadata: typeof privatePageMetadata) => head.replace(
  /<!--hush-head-start-->[\s\S]*?<!--hush-head-end-->/,
  () => renderPageHead(metadata),
);
// The landing scene is imported only after the application starts, and its
// lighting texture only after the 3D engine has loaded. On a first visit that
// waterfall missed the entrance's fallback deadline, so landing pages announce
// the scene's chunks and texture in the head and the browser fetches them with
// the application.
type ManifestChunk = { file: string; isEntry?: boolean; imports?: string[]; assets?: string[] };
const manifest: Record<string, ManifestChunk> = await Bun.file("dist/.vite/manifest.json").json();
const sceneKey = Object.keys(manifest).find((key) => key.endsWith("src/landing/HushScene.ts"));
if (!sceneKey) throw new Error("Missing the landing scene in the build manifest");
const sceneFiles = new Set<string>(), sceneAssets = new Set<string>();
(function collect(key: string) {
  const chunk = manifest[key]!;
  // The application entry is already loaded by the page itself.
  if (chunk.isEntry || sceneFiles.has(chunk.file)) return;
  sceneFiles.add(chunk.file);
  for (const asset of chunk.assets ?? []) if (asset.includes(".ktx2")) sceneAssets.add(asset);
  for (const imported of chunk.imports ?? []) collect(imported);
})(sceneKey);
if (!sceneAssets.size) throw new Error("Missing the landing scene's lighting texture in the build manifest");
const scenePreloads = [
  ...[...sceneFiles].map((file) => `<link rel="modulepreload" href="/${file}">`),
  // Matches the scene's same-origin fetch(), so the browser reuses this download.
  ...[...sceneAssets].map((file) => `<link rel="preload" href="/${file}" as="fetch" crossorigin="anonymous">`),
].join("");
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
  html = html.replace("<head>", () => `<head>${pageHead(metadata)}${landingPaths.includes(path) ? scenePreloads : ""}`);
  const externalized = externalizeScripts(html);
  for (const asset of externalized.assets) await Bun.write(`dist${asset.path}`, asset.code);
  pages[path] = externalized.html;
}
// The build manifest is only for this script; never serve it.
await rm("dist/.vite", { recursive: true, force: true });
// Kept outside the public static directory. Only explicit server routes serve it.
await Bun.write("dist-pages/pages.json", JSON.stringify(pages));
// The client-only shell serves private proofs and unknown release pages only.
await Bun.write("dist/index.html", template.replace(/<head>[\s\S]*?<\/head>/, () => `<head>${pageHead(privatePageMetadata)}</head>`));
console.info(`Prerendered ${Object.keys(pages).length} public documents. No message proofs were rendered.`);
