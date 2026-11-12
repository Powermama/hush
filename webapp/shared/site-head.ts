// SPDX-License-Identifier: AGPL-3.0-only
// Copyright 2026 Clemens Kressmann
import type { BlogPosting } from "schema-dts";
import { siteOrigin, softwareDescription, type PageMetadata } from "./site.ts";

const escapeHTML = (value: string) => value.replaceAll("&", "&amp;").replaceAll('"', "&quot;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");

/** Only trusted public catalogue entries belong here, never proof contents. */
export function renderPageHead(page: PageMetadata): string {
  const title = escapeHTML(page.title);
  const description = escapeHTML(page.description);
  const canonical = escapeHTML(`${siteOrigin}${page.canonicalPath}`);
  const article = page.article;
  const verified = page.canonicalPath === "/verified-messages";
  const image = `${siteOrigin}/social/${verified ? "verified-messages" : "hush"}.png`;
  const imageAlt = article ? article.imageAlt : verified
    ? "Give your words their story back. A hush message mock-up with signed capture and edit history."
    : "The voice layer for your Mac. The hush listening HUD with a waveform beside an example message.";
  // Dates are day-precise in the source; publish them as UTC midnight.
  const isoDate = (date: string) => `${date}T00:00:00Z`;
  const articleData = article && {
    "@context": "https://schema.org",
    "@type": "BlogPosting",
    headline: article.heading,
    description: page.description,
    inLanguage: page.language,
    mainEntityOfPage: `${siteOrigin}${page.canonicalPath}`,
    url: `${siteOrigin}${page.canonicalPath}`,
    image: [image],
    datePublished: isoDate(article.published),
    dateModified: isoDate(article.modified),
    author: { "@type": "Person", name: article.author, url: article.authorUrl },
    publisher: { "@type": "Organization", name: "hush", url: siteOrigin },
  } satisfies BlogPosting & { "@context": string };
  return [
    `<title>${title}</title>`,
    `<meta name="description" content="${description}">`,
    `<meta name="robots" content="${page.indexable ? "index, follow" : "noindex, nofollow"}">`,
    ...(page.indexable || page.canonicalPath !== "/" ? [`<link rel="canonical" href="${canonical}">`] : []),
    `<meta property="og:type" content="${article ? "article" : "website"}">`,
    ...(article ? [
      `<meta property="article:published_time" content="${isoDate(article.published)}">`,
      `<meta property="article:modified_time" content="${isoDate(article.modified)}">`,
      `<meta property="article:author" content="${escapeHTML(article.authorUrl)}">`,
    ] : []),
    `<meta property="og:site_name" content="hush">`,
    `<meta property="og:title" content="${title}">`,
    `<meta property="og:description" content="${description}">`,
    `<meta property="og:url" content="${canonical}">`,
    `<meta property="og:locale" content="${page.language === "de" ? "de_DE" : "en_US"}">`,
    `<meta property="og:image" content="${image}">`,
    `<meta property="og:image:type" content="image/png">`,
    `<meta property="og:image:width" content="1200">`,
    `<meta property="og:image:height" content="630">`,
    `<meta property="og:image:alt" content="${escapeHTML(imageAlt)}">`,
    `<meta name="twitter:card" content="summary_large_image">`,
    `<meta name="twitter:title" content="${title}">`,
    `<meta name="twitter:description" content="${description}">`,
    `<meta name="twitter:image" content="${image}">`,
    `<meta name="twitter:image:alt" content="${escapeHTML(imageAlt)}">`,
    ...(page.indexable ? ['<link rel="describedby" href="/llms.txt" type="text/plain">'] : []),
    ...(page.alternatePaths ? Object.entries({ ...page.alternatePaths, "x-default": page.alternatePaths.en }).map(([lang, path]) => `<link rel="alternate" hreflang="${lang}" href="${siteOrigin}${path}">`) : []),
    ...(page.canonicalPath === "/" && page.indexable ? [`<script type="application/ld+json">${JSON.stringify(softwareDescription).replaceAll("<", "\\u003c")}</script>`] : []),
    ...(articleData ? [`<script type="application/ld+json">${JSON.stringify(articleData).replaceAll("<", "\\u003c")}</script>`] : []),
  ].join("\n");
}
