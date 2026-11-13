// SPDX-License-Identifier: AGPL-3.0-only
// Copyright 2026 Clemens Kressmann
import type { BlogPosting, BreadcrumbList, Person, ProfilePage } from "schema-dts";
import { blogCopy } from "./blog.ts";
import { authorPath, blogAuthors, type BlogAuthorId } from "@hush/article/authors";
import { landingPaths, organizationData, siteOrigin, softwareDescription, websiteData, type PageMetadata } from "./site.ts";

const escapeHTML = (value: string) => value.replaceAll("&", "&amp;").replaceAll('"', "&quot;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");

/** The author as one schema.org Person, identified by their profile page. */
function personData(id: BlogAuthorId, language: "en" | "de") {
  const author = blogAuthors[id];
  const url = `${siteOrigin}${authorPath(language, id)}`;
  return {
    "@type": "Person", "@id": `${url}#person`, name: author.name, url,
    description: author.bio[language], jobTitle: author.role[language],
    ...("image" in author ? { image: `${siteOrigin}${author.image}` } : {}),
    sameAs: author.sameAs.map((profile) => profile.url),
  } satisfies Person;
}


/** Only trusted public catalogue entries belong here, never proof contents. */
export function renderPageHead(page: PageMetadata): string {
  const title = escapeHTML(page.title);
  const description = escapeHTML(page.description);
  const canonical = escapeHTML(`${siteOrigin}${page.canonicalPath}`);
  const article = page.article;
  const verified = page.canonicalPath === "/verified-messages";
  const image = `${siteOrigin}${article ? article.image : `/social/${verified ? "verified-messages" : "hush"}.png`}`;
  const imageAlt = article ? article.imageAlt : verified
    ? "Give your words their story back. A hush message mock-up with signed capture and edit history."
    : page.language === "de"
      ? "Die Sprachebene für den Mac. Das hush HUD hört zu, mit Wellenform neben einer Beispielnachricht."
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
    author: personData(article.author, page.language),
    publisher: organizationData,
  } satisfies BlogPosting & { "@context": string };
  // Articles and author pages sit under the blog: Home > Blog > page.
  const blog = blogCopy[page.language];
  const breadcrumbData = (article || page.profile) && {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: [
      { "@type": "ListItem", position: 1, name: "hush", item: `${siteOrigin}/` },
      { "@type": "ListItem", position: 2, name: blog.heading, item: `${siteOrigin}${blog.indexPath}` },
      { "@type": "ListItem", position: 3, name: article ? article.heading : blogAuthors[page.profile!.author].name },
    ],
  } satisfies BreadcrumbList & { "@context": string };
  const profileData = page.profile && {
    "@context": "https://schema.org",
    "@type": "ProfilePage",
    url: `${siteOrigin}${page.canonicalPath}`,
    inLanguage: page.language,
    dateModified: page.modified && isoDate(page.modified),
    mainEntity: personData(page.profile.author, page.language),
  } satisfies ProfilePage & { "@context": string };
  // The home page names the site and its publisher for search engines.
  const homeData = page.canonicalPath === "/" && page.indexable
    ? [websiteData, { "@context": "https://schema.org", ...organizationData }]
    : [];
  return [
    `<title>${title}</title>`,
    `<meta name="description" content="${description}">`,
    `<meta name="robots" content="${page.indexable ? "index, follow" : "noindex, nofollow"}">`,
    ...(page.indexable || page.canonicalPath !== "/" ? [`<link rel="canonical" href="${canonical}">`] : []),
    `<meta property="og:type" content="${article ? "article" : page.profile ? "profile" : "website"}">`,
    ...(article ? [
      `<meta property="article:published_time" content="${isoDate(article.published)}">`,
      `<meta property="article:modified_time" content="${isoDate(article.modified)}">`,
      `<meta property="article:author" content="${siteOrigin}${authorPath(page.language, article.author)}">`,
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
    ...(landingPaths.includes(page.canonicalPath) && page.indexable ? [`<script type="application/ld+json">${JSON.stringify(softwareDescription(page)).replaceAll("<", "\\u003c")}</script>`] : []),
    // Language choice (public/language.js): async, so it never blocks the first paint.
    ...(page.alternatePaths ? ['<script src="/language.js" async></script>'] : []),
    ...[...homeData, articleData, profileData, breadcrumbData].filter(Boolean).map((data) => `<script type="application/ld+json">${JSON.stringify(data).replaceAll("<", "\\u003c")}</script>`),
  ].join("\n");
}
