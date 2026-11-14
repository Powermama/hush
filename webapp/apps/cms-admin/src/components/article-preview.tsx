// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The rendered article as behu.sh shows it, from the CMS's preview. It runs in
// a sandboxed frame that may run no scripts, so author content never executes
// on the admin's origin, which holds the session. Unlike a fully sandboxed
// frame it keeps that origin, as Ghost's preview is a page of its own site:
// the article's images then load as the admin's own (img-src 'self',
// Cross-Origin-Resource-Policy same-origin). Allowing the origin is safe only
// without allow-scripts; never add both.
import articleCss from "@hush/article/article.css?raw";

const page = (heading: string, html: string) => `<!doctype html><html lang="en"><head><meta charset="utf-8">
<style>
:root { --color-ink: #1f201e; --color-muted: #686963; --color-soft: #a7a8a1; }
* { box-sizing: border-box; }
body { margin: 0; padding: 40px 24px 80px; background: #fff; color: var(--color-ink);
  font-family: "SF Pro Text", -apple-system, BlinkMacSystemFont, "Segoe UI", Inter, Roboto, sans-serif; -webkit-font-smoothing: antialiased; }
main { max-width: 680px; margin: 0 auto; }
/* As .blog-article-header h1 on behu.sh. */
h1 { font-size: clamp(32px, 5vw, 48px); line-height: 1.1; letter-spacing: -0.035em; font-weight: 600; margin: 0 0 40px; color: var(--color-ink); text-wrap: balance; }
${articleCss}
</style></head><body><main><h1>${heading.replace(/[&<>"]/g, (c) => `&#${c.charCodeAt(0)};`)}</h1><div class="blog-prose">${html}</div></main></body></html>`;

export function ArticlePreview({ heading, html }: { heading: string; html: string }) {
  return <iframe title="Preview" sandbox="allow-same-origin" srcDoc={page(heading, html)} className="h-full min-h-[70vh] w-full rounded-lg border border-border bg-white" />;
}
