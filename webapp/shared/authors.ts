// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Blog authors. Articles name an author by id in their front matter; the build
// rejects unknown ids. Each author gets a profile page per blog language, which
// bylines and BlogPosting data link to, with sameAs links to the same person
// elsewhere (Google's author markup guidance).
import type { BlogLanguage } from "./blog.ts";

export type BlogAuthor = {
  name: string;
  /** Profiles of the same person, in the order they are shown. */
  sameAs: Array<{ label: string; url: string }>;
  role: Record<BlogLanguage, string>;
  bio: Record<BlogLanguage, string>;
};

export const blogAuthors = {
  "clemens-kressmann": {
    name: "Clemens Kressmann",
    sameAs: [
      { label: "LinkedIn", url: "https://www.linkedin.com/in/clemens-kressmann/" },
      { label: "GitHub", url: "https://github.com/Powermama" },
    ],
    role: {
      en: "Entrepreneur, maker of hush",
      de: "Unternehmer, Entwickler von hush",
    },
    bio: {
      en: "Clemens Kressmann is an entrepreneur driven by the idea of decentral freedom: software that runs on your own devices and stays in your hands. His work runs from business through UI design to programming, and he builds open-source projects, including hush, a dictation and AI app for the Mac.",
      de: "Clemens Kressmann ist Unternehmer und folgt der Idee der dezentralen Freiheit: Software, die auf eigenen Geräten läuft und in der eigenen Hand bleibt. Seine Arbeit reicht vom Geschäftlichen über UI-Design bis zur Programmierung. Er entwickelt Open-Source-Projekte, darunter hush, eine Diktier- und KI-App für den Mac.",
    },
  },
} as const satisfies Record<string, BlogAuthor>;

export type BlogAuthorId = keyof typeof blogAuthors;
export const blogAuthorIds = Object.keys(blogAuthors) as [BlogAuthorId, ...BlogAuthorId[]];

export function authorPath(lang: BlogLanguage, id: BlogAuthorId) {
  return lang === "de" ? `/de/autoren/${id}` : `/authors/${id}`;
}
