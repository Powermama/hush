// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
export type BlogLanguage = "en" | "de";

/** Public metadata of a published article. Generated; HTML lives in its own chunk. */
export type BlogPostMetadata = {
  slug: string;
  lang: BlogLanguage;
  path: string;
  title: string;
  description: string;
  heading: string;
  type: "how-to" | "comparison" | "guide" | "listicle" | "news";
  cluster: string;
  author: string;
  authorUrl: string;
  published: string;
  updated: string;
  imageAlt: string;
  readingMinutes: number;
  toc: ReadonlyArray<{ id: string; text: string }>;
};

export const blogCopy = {
  en: {
    indexPath: "/blog",
    indexTitle: "hush blog - Dictation and local AI on Mac",
    indexDescription: "Practical guides to voice dictation, speech-to-text and local AI on Mac, written by the team that builds hush, the free and open-source dictation app.",
    heading: "The hush blog",
    lead: "Practical guides to dictation, speech-to-text and local AI on Mac.",
    readingTime: (minutes: number) => `${minutes} min read`,
    published: "Published",
    updated: "Updated",
    onThisPage: "On this page",
    related: "Keep reading",
    allArticles: "All articles",
    ctaTitle: "Dictate on your Mac, with models that run locally",
    ctaBody: "hush is free and open source. Your dictation and AI models run on your Mac; web search, model downloads, updates and optional Verified Messages use the internet.",
    by: "By",
  },
  de: {
    indexPath: "/de/blog",
    indexTitle: "hush Blog - Diktieren und lokale KI auf dem Mac",
    indexDescription: "Praktische Anleitungen zu Diktat, Spracherkennung und lokaler KI auf dem Mac, geschrieben vom Team hinter hush, der kostenlosen Open-Source-Diktier-App.",
    heading: "Der hush Blog",
    lead: "Praktische Anleitungen zu Diktat, Spracherkennung und lokaler KI auf dem Mac.",
    readingTime: (minutes: number) => `${minutes} Min. Lesezeit`,
    published: "Veröffentlicht",
    updated: "Aktualisiert",
    onThisPage: "Auf dieser Seite",
    related: "Weiterlesen",
    allArticles: "Alle Artikel",
    ctaTitle: "Diktieren auf dem Mac, mit Modellen, die lokal laufen",
    ctaBody: "hush ist kostenlos und Open Source. Diktat und KI-Modelle laufen auf dem Mac; Websuche, Modell-Downloads, Updates und optionale Verified Messages nutzen das Internet.",
    by: "Von",
  },
} as const;
