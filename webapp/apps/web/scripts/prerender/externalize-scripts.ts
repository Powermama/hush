// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { createHash } from "node:crypto";
import { parse, type DefaultTreeAdapterTypes } from "parse5";

type ScriptAsset = { path: string; code: string };

/**
 * Extract trusted SSR scripts for CSP. This is not an untrusted-HTML sanitizer.
 *
 * The scripts carry the router's hydration data ($_TSR), which the app module
 * reads as it starts. With a module on the page they move in front of it as
 * deferred scripts: deferred and module scripts run in document order once the
 * document is parsed, so the data is always there first and never blocks the
 * first paint. Left at the end of the body, a browser could start the module
 * before them, and the page went blank.
 */
export function externalizeScripts(html: string) {
  const document = parse(html, { sourceCodeLocationInfo: true });
  const edits: { start: number; end: number; replacement: string }[] = [];
  const assets = new Map<string, ScriptAsset>();
  const scripts: { start: number; end: number; path: string }[] = [];
  let module: number | undefined;

  function visit(node: DefaultTreeAdapterTypes.Node) {
    if ("tagName" in node && node.tagName === "script" && module === undefined &&
        node.attrs.some(attribute => attribute.name === "type" && attribute.value === "module")) {
      module = node.sourceCodeLocation?.startOffset;
    }
    if ("tagName" in node && node.tagName === "script" &&
        node.namespaceURI === "http://www.w3.org/1999/xhtml" && node.attrs.length === 0) {
      const location = node.sourceCodeLocation;
      if (!location?.startTag || !location.endTag) {
        throw new Error("Cannot externalize an unclosed SSR script");
      }
      // Read source offsets rather than normalized parser text: HTML parsing
      // replaces NULs, but TanStack hydration identifiers must retain them.
      const code = html.slice(location.startTag.endOffset, location.endTag.startOffset)
        .replaceAll("\u0000", "\\u0000");
      const digest = createHash("sha256").update(code).digest("hex").slice(0, 16);
      const path = `/assets/route-${digest}.js`;
      assets.set(path, { path, code });
      scripts.push({ start: location.startOffset, end: location.endOffset, path });
    }
    // Template content has its own fragment and is intentionally not traversed.
    // Comment and noscript text are not executable script elements either.
    if ("childNodes" in node) node.childNodes.forEach(visit);
  }
  visit(document);
  if (module === undefined) {
    // No module to race: each script stays where it was.
    for (const { start, end, path } of scripts) edits.push({ start, end, replacement: `<script src="${path}"></script>` });
  } else if (scripts.length) {
    for (const { start, end } of scripts) edits.push({ start, end, replacement: "" });
    const deferred = scripts.map(({ path }) => `<script defer src="${path}"></script>`).join("");
    edits.push({ start: module, end: module, replacement: deferred });
  }
  // Replace by source position so identical text in comments stays untouched.
  for (const edit of edits.sort((a, b) => b.start - a.start)) {
    html = html.slice(0, edit.start) + edit.replacement + html.slice(edit.end);
  }
  return { html, assets: [...assets.values()] };
}
