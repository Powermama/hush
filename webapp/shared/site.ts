// SPDX-License-Identifier: AGPL-3.0-only
// Copyright 2026 Clemens Kressmann
import { legalConfig } from "./legal.ts";
import { releases, releasePath } from "./releases.ts";
import { blogCopy, type BlogLanguage } from "./blog.ts";
import { blogPosts } from "./blog-posts.generated.ts";
import { authorPath, blogAuthors, type BlogAuthorId } from "./authors.ts";

export const siteOrigin = "https://behu.sh";
export type PageMetadata = {
  title: string;
  description: string;
  canonicalPath: string;
  indexable: boolean;
  language: "en" | "de";
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
    title: "hush - Local voice dictation and AI for Mac",
    description: "Free, open-source voice dictation for Mac. Write across your apps with local AI, personal writing styles and a beta assistant. Built for Apple silicon.",
    canonicalPath: "/", indexable: true, language: "en",
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

export const softwareDescription = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: "hush",
  url: siteOrigin,
  description: sitePages["/"]!.description,
  applicationCategory: "ProductivityApplication",
  operatingSystem: "macOS 15 or later",
  processorRequirements: "Apple silicon (M1 or later)",
  isAccessibleForFree: true,
  license: "https://github.com/Powermama/hush/blob/main/LICENSING.md",
  sameAs: ["https://github.com/Powermama/hush"],
};

/** Site paths that exist independently of the blog (blog articles may link to them). */
export function staticSitePaths(): string[] {
  return Object.keys(sitePages).filter((path) => !/^(\/de)?\/(blog|authors|autoren)(\/|$)/.test(path));
}

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
