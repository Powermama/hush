// SPDX-License-Identifier: AGPL-3.0-only
// Copyright 2026 Clemens Kressmann
import { legalConfig } from "./legal.ts";
import { releases, releasePath } from "./releases.ts";
import { editorialPolicyPath, type BlogLanguage } from "@hush/article/taxonomy";
import { blogCopy } from "./blog.ts";
import { blogPosts } from "./blog-posts.generated.ts";
import { authorPath, blogAuthors, type BlogAuthorId } from "@hush/article/authors";

export const siteOrigin = "https://behu.sh";
export type SiteLanguage = "en" | "de";
export type PageMetadata = {
  title: string;
  description: string;
  canonicalPath: string;
  indexable: boolean;
  language: SiteLanguage;
  alternatePaths?: { en: string; de: string };
  modified?: string;
  /** Present for blog articles: drives og:type article and BlogPosting data. */
  article?: {
    heading: string;
    author: BlogAuthorId;
    published: string;
    modified: string;
    imageAlt: string;
    /** Site path of the 1200x630 social preview. */
    image: string;
  };
  /** Present for author pages: drives ProfilePage data. */
  profile?: { author: BlogAuthorId };
};

export const sitePages: Record<string, PageMetadata> = {
  "/": {
    title: "hush - Free Dictation App for Mac, Speech to Text",
    description: "Free, open-source voice dictation for Mac. Write across your apps with local AI, personal writing styles and a beta assistant. Built for Apple silicon.",
    canonicalPath: "/", indexable: true, language: "en",
    alternatePaths: { en: "/", de: "/de" },
  },
  "/de": {
    title: "hush - Kostenlose Diktier-App für den Mac mit lokaler KI",
    description: "Kostenlose Open-Source-Diktier-App für den Mac: Sprache zu Text in allen Apps, mit lokaler KI, eigenen Schreibstilen und Beta-Assistent. Für Apple Silicon.",
    canonicalPath: "/de", indexable: true, language: "de",
    alternatePaths: { en: "/", de: "/de" },
  },
  "/verified-messages": {
    title: "Verified Messages - Signed message history with hush",
    description: "Record in hush. Keep the recorded time and edits. Share a private encrypted link so readers can verify the signed message history in their browser.",
    canonicalPath: "/verified-messages", indexable: true, language: "en",
  },
  "/releases": {
    title: "hush release notes",
    description: "See what is new, improved, and fixed in every hush release.",
    canonicalPath: "/releases", indexable: releases.some(r => r.visibility === "public"), language: "en",
  },
};

for (const language of ["en", "de"] as const) {
  for (const page of ["impressum", "datenschutz"] as const) {
    const path = `${language === "de" ? "/de" : ""}/${page}`;
    const privacy = page === "datenschutz";
    sitePages[path] = {
      title: `${language === "de" ? privacy ? "Datenschutzerklärung" : "Impressum" : privacy ? "Privacy policy" : "Legal notice"} - hush`,
      description: language === "de"
        ? privacy ? "Wie hush auf der Website, beim Download und bei optionalen Verified Messages mit Daten umgeht." : "Anbieterkennzeichnung und Kontakt für hush."
        : privacy ? "How hush handles data on the website, during downloads and for optional Verified Messages." : "Provider identification and contact information for hush.",
      canonicalPath: path, language, indexable: !legalConfig.isPlaceholder,
      alternatePaths: { en: `/${page}`, de: `/de/${page}` },
    };
  }
}
for (const release of releases) {
  const path = releasePath(release);
  sitePages[path] = {
    title: `hush ${release.displayVersion} release notes`,
    description: release.summary, canonicalPath: path,
    indexable: release.visibility === "public", language: "en", modified: release.releasedAt,
  };
}

export const privatePageMetadata: PageMetadata = {
  title: "Private message proof - hush",
  description: "Open a private hush link to verify its signed message history in your browser.",
  canonicalPath: "/", indexable: false, language: "en",
};

/** The not-found page, prerendered once per language and served with status 404. */
export const notFoundPages: Record<SiteLanguage, PageMetadata> = {
  en: { title: "Page not found - hush", description: "This page does not exist on behu.sh.", canonicalPath: "/", indexable: false, language: "en" },
  de: { title: "Seite nicht gefunden - hush", description: "Diese Seite gibt es auf behu.sh nicht.", canonicalPath: "/de", indexable: false, language: "de" },
};
/** Prerendered documents for unknown addresses, keyed in pages.json by language. */
export const notFoundDocumentKey = (language: SiteLanguage) => `404:${language}`;

/** The publisher everywhere in structured data; its logo is what Google shows for the brand. */
export const organizationData = {
  "@type": "Organization",
  "@id": `${siteOrigin}/#organization`,
  name: "hush",
  url: `${siteOrigin}/`,
  logo: { "@type": "ImageObject", url: `${siteOrigin}/logo.png`, width: 512, height: 512 },
  sameAs: ["https://github.com/Powermama/hush"],
};

/** The site's name in search results (https://developers.google.com/search/docs/appearance/site-names). */
export const websiteData = {
  "@context": "https://schema.org",
  "@type": "WebSite",
  "@id": `${siteOrigin}/#website`,
  name: "hush",
  alternateName: ["hush for Mac", "behu.sh"],
  url: `${siteOrigin}/`,
  publisher: { "@id": organizationData["@id"] },
};

/** SoftwareApplication data for a landing page in its language; free is stated as a zero-price offer. */
export const softwareDescription = (page: PageMetadata) => ({
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: "hush",
  url: `${siteOrigin}${page.canonicalPath}`,
  description: page.description,
  inLanguage: page.language,
  applicationCategory: "ProductivityApplication",
  operatingSystem: "macOS 15 or later",
  processorRequirements: "Apple silicon (M1 or later)",
  isAccessibleForFree: true,
  offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
  license: "https://github.com/Powermama/hush/blob/main/LICENSING.md",
  sameAs: ["https://github.com/Powermama/hush"],
  publisher: { "@id": organizationData["@id"] },
});

/** Pages that are a landing page, in either language. */
export const landingPaths = ["/", "/de"];

/** Site paths that exist independently of the blog (blog articles may link to them). */
// Blog pages exist only for languages with at least one published article, so
// an empty blog is never served or indexed.
for (const lang of ["en", "de"] as BlogLanguage[]) {
  const articles = blogPosts.filter((post) => post.lang === lang);
  if (!articles.length) continue;
  const copy = blogCopy[lang];
  sitePages[copy.indexPath] = {
    title: copy.indexTitle, description: copy.indexDescription, canonicalPath: copy.indexPath,
    indexable: true, language: lang, modified: articles.map((post) => post.updated).sort().at(-1),
  };
  for (const post of articles) {
    sitePages[post.path] = {
      title: post.title, description: post.description, canonicalPath: post.path,
      indexable: true, language: lang, modified: post.updated,
      article: {
        heading: post.heading, author: post.author,
        published: post.published, modified: post.updated, imageAlt: post.imageAlt, image: post.socialImage,
      },
    };
  }
  sitePages[editorialPolicyPath(lang)] = {
    title: copy.editorialTitle, description: copy.editorialDescription,
    canonicalPath: editorialPolicyPath(lang), indexable: true, language: lang,
  };
  for (const author of new Set(articles.map((post) => post.author))) {
    // build-blog rejects unknown authors; this only skips stale generated data
    // while the generator itself imports this module to regenerate it.
    if (!(author in blogAuthors)) continue;
    const path = authorPath(lang, author);
    const own = articles.filter((post) => post.author === author);
    const { name, role } = blogAuthors[author];
    sitePages[path] = {
      title: `${name} - ${role[lang]}`,
      description: copy.authorDescription(name),
      canonicalPath: path, indexable: true, language: lang,
      modified: own.map((post) => post.updated).sort().at(-1), profile: { author },
    };
  }
}
