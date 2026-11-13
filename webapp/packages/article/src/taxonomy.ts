// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The vocabulary articles are written in: languages, topic clusters, article
// types and the blog's URL scheme. Shared by the website and the CMS.

export const blogLanguages = ["en", "de"] as const;
export type BlogLanguage = (typeof blogLanguages)[number];

export const blogArticleTypes = ["how-to", "comparison", "guide", "listicle", "essay", "news"] as const;
export type BlogArticleType = (typeof blogArticleTypes)[number];

/**
 * Topic clusters from the content strategy (hush-seo skill). Articles name one by
 * id; the label appears on covers and cards. Unknown ids fail validation.
 */
export const blogClusters = {
  "local-dictation": { en: "Dictation without the cloud", de: "Diktat ohne Cloud" },
  "dictation-on-mac": { en: "Dictation on Mac", de: "Diktat auf dem Mac" },
  "local-ai": { en: "Local AI", de: "Lokale KI" },
  "speech-models": { en: "Speech models", de: "Sprachmodelle" },
  "voice-writing": { en: "Writing by voice", de: "Schreiben per Stimme" },
  "typing-less": { en: "Typing less", de: "Weniger tippen" },
  "verified-messages": { en: "Verified Messages", de: "Verified Messages" },
} as const satisfies Record<string, Record<BlogLanguage, string>>;

export type BlogClusterId = keyof typeof blogClusters;
export const blogClusterIds = Object.keys(blogClusters) as [BlogClusterId, ...BlogClusterId[]];

export function blogPath(lang: BlogLanguage, slug?: string) {
  const base = lang === "de" ? "/de/blog" : "/blog";
  return slug ? `${base}/${slug}` : base;
}

/** The editorial policy lives under each blog; its slug is reserved for articles. */
export const editorialPolicySlugs: Record<BlogLanguage, string> = { en: "editorial-policy", de: "redaktionelle-richtlinien" };
export function editorialPolicyPath(lang: BlogLanguage) {
  return blogPath(lang, editorialPolicySlugs[lang]);
}

/**
 * Site pages outside the blog that articles may link to. The website checks that
 * each one exists; link to /releases rather than a single release.
 */
export const linkableSitePaths: readonly string[] = [
  "/", "/de", "/verified-messages", "/releases",
  "/impressum", "/datenschutz", "/de/impressum", "/de/datenschutz",
];
