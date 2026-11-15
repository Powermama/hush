// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { blogPath, type BlogLanguage } from "@hush/article/taxonomy";

/** The website the blog is published on. */
export const siteOrigin = "https://behu.sh";

/** Where a post lives on the website: https://behu.sh/blog/<slug>, or /de/blog/<slug> in German. */
export function articleUrl(lang: string, slug: string) {
  return `${siteOrigin}${blogPath(lang === "de" ? "de" : "en" satisfies BlogLanguage, slug)}`;
}

/** The same address without its scheme, as Ghost previews a post's URL. */
export function articleUrlPreview(lang: string, slug: string) {
  return articleUrl(lang, slug || "…").replace(/^https:\/\//, "");
}
