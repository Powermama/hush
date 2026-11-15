// SPDX-License-Identifier: AGPL-3.0-only
// Copyright 2026 Clemens Kressmann
import { landingPaths, sitePages, siteOrigin, privatePageMetadata, notFoundPages, notFoundDocumentKey, type SiteLanguage } from "../shared/site";
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
type ManifestChunk = { file: string; isEntry?: boolean; imports?: string[]; assets?: string[]; css?: string[] };
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
// Every page loads its own code on demand (src/app/router.tsx). Its chunks are
// announced in the head, so the browser fetches them with the application
// instead of after it, and hydration waits for no second round trip.
const pageModules: Record<string, string> = {
  "/": "src/app/App.tsx",
  "/de": "src/landing/GermanLanding.tsx",
  "/verified-messages": "src/verified/VerifiedMessagesPage.tsx",
  "/releases": "src/releases/ReleaseNotesPage.tsx",
  "/releases/latest": "src/releases/ReleaseNotesPage.tsx",
  "/impressum": "src/legal/LegalPages.tsx",
  "/datenschutz": "src/legal/LegalPages.tsx",
  "/de/impressum": "src/legal/LegalPages.tsx",
  "/de/datenschutz": "src/legal/LegalPages.tsx",
};
function pageModule(path: string) {
  if (pageModules[path]) return pageModules[path];
  if (path.startsWith("/releases/")) return "src/releases/ReleaseRoute.tsx";
  // Articles; the blog index, author and policy pages are part of the application itself.
  const article = /^(?:\/(de))?\/blog\/([a-z0-9-]+)$/.exec(path);
  const key = article && `src/blog/generated/${article[1] ?? "en"}/${article[2]}.tsx`;
  return key && manifest[key] ? key : undefined;
}
function pagePreloads(path: string) {
  const key = pageModule(path);
  if (!key) return "";
  if (!manifest[key]) throw new Error(`Missing ${key}, the code of ${path}, in the build manifest`);
  const files = new Set<string>(), styles = new Set<string>();
  (function collect(chunkKey: string) {
    const chunk = manifest[chunkKey]!;
    // The application entry is already loaded by the page itself.
    if (chunk.isEntry || files.has(chunk.file)) return;
    files.add(chunk.file);
    for (const style of chunk.css ?? []) styles.add(style);
    for (const imported of chunk.imports ?? []) collect(imported);
  })(key);
  // A page's own styles block rendering like the application's: linked by its
  // JavaScript instead, the prerendered page would first paint unstyled (a
  // full-screen logo on the landing). Vite's loader finds them already linked.
  return [
    ...[...styles].map((file) => `<link rel="stylesheet" crossorigin href="/${file}">`),
    ...[...files].map((file) => `<link rel="modulepreload" crossorigin href="/${file}">`),
  ].join("");
}
/** The resource hints a head does not announce yet, each once. */
function withoutRepeats(documentHead: string, hints: string) {
  const seen = new Set([...documentHead.matchAll(/href="([^"]+)"/g)].map((match) => match[1]));
  return [...hints.matchAll(/<link [^>]*href="([^"]+)"[^>]*>/g)]
    .filter((match) => !seen.has(match[1]) && Boolean(seen.add(match[1])))
    .map((match) => match[0]).join("");
}
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
  const documentHead = pageHead(metadata);
  const hints = withoutRepeats(documentHead, pagePreloads(path) + (landingPaths.includes(path) ? scenePreloads : ""));
  html = html.replace("<head>", () => `<head>${documentHead}${hints}`);
  const externalized = externalizeScripts(html);
  for (const asset of externalized.assets) await Bun.write(`dist${asset.path}`, asset.code);
  pages[path] = externalized.html;
}
// Unknown addresses get the not-found page in the address's language, sent by the
// server with status 404. The router renders it for any path no route matches.
for (const [language, metadata] of Object.entries(notFoundPages) as [SiteLanguage, typeof privatePageMetadata][]) {
  const response = await render(`${siteOrigin}${language === "de" ? "/de" : ""}/__not-found`);
  let html = await response.text();
  if (response.status !== 404 || !html.includes('id="not-found-title"')) {
    throw new Error(`Cannot prerender the ${language} not-found page: ${response.status}`);
  }
  html = html.replace('<html lang="en">', `<html lang="${language}">`);
  html = html.replace("<head>", () => `<head>${pageHead(metadata)}`);
  const externalized = externalizeScripts(html);
  for (const asset of externalized.assets) await Bun.write(`dist${asset.path}`, asset.code);
  pages[notFoundDocumentKey(language)] = externalized.html;
}
// The build manifest is only for this script; never serve it.
await rm("dist/.vite", { recursive: true, force: true });
// Kept outside the public static directory. Only explicit server routes serve it.
await Bun.write("dist-pages/pages.json", JSON.stringify(pages));
// The client-only shell serves private proofs and unknown release pages only.
await Bun.write("dist/index.html", template.replace(/<head>[\s\S]*?<\/head>/, () => `<head>${pageHead(privatePageMetadata)}</head>`));
console.info(`Prerendered ${Object.keys(pages).length} public documents. No message proofs were rendered.`);
