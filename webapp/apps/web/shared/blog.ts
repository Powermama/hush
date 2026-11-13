// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import type { BlogAuthorId } from "@hush/article/authors";
import type { BlogArticleType, BlogClusterId, BlogLanguage } from "@hush/article/taxonomy";

/** Public metadata of a published article. Generated; HTML lives in its own chunk. */
export type BlogPostMetadata = {
  slug: string;
  lang: BlogLanguage;
  path: string;
  title: string;
  description: string;
  heading: string;
  type: BlogArticleType;
  cluster: BlogClusterId;
  author: BlogAuthorId;
  published: string;
  updated: string;
  imageAlt: string;
  readingMinutes: number;
  toc: ReadonlyArray<{ id: string; text: string }>;
  /** A 1200x630 PNG used only in link previews and structured data. */
  socialImage: string;
  /** The same artwork as an 800px WebP for article cards. */
  cardImage: string;
};

export const blogCopy = {
  en: {
    indexPath: "/blog",
    indexTitle: "hush blog - Dictation and local AI on Mac",
    indexDescription: "Practical guides to voice dictation, speech-to-text and local AI on Mac, written by the team that builds hush, the free and open-source dictation app.",
    heading: "The hush blog",
    lead: "Practical guides to dictation, speech-to-text and local AI on Mac.",
    readingTime: (minutes: number) => `${minutes} min read`,
    readingTimeShort: (minutes: number) => `${minutes} min`,
    published: "Published",
    updated: "Updated",
    related: "Keep reading",
    allArticles: "All articles",
    readArticle: "Read article",
    topics: "Topics",
    allTopics: "All",
    editorialTitle: "Editorial policy - hush blog",
    editorialHeading: "Editorial policy",
    editorialDescription: "How the hush blog researches, tests, writes and corrects its articles: primary sources with dates, our own tests, reviewed AI use and no affiliate links.",
    writtenBy: "Written by",
    share: "Share",
    copyLink: "Copy link",
    linkCopied: "Link copied",
    shareOn: (network: string) => `Share on ${network}`,
    shareByEmail: "Share by email",
    viewProfile: "View profile",
    authorDescription: (name: string) => `Articles by ${name} on dictation, speech-to-text and local AI on Mac, with background and profiles.`,
    authorArticles: "Articles",
    authorElsewhere: "Elsewhere",
    ctaTitle: "Dictate on your Mac, with models that run locally",
    ctaDownload: "Download for Mac",
    ctaMobile: "Get hush for Mac",
    // The download card replays one dictation; HUD labels match the app.
    // The download band replays one dictation per loop, each into an app with its own look.
    // App names and HUD labels match the app, which is in English.
    ctaDemos: [
      { kind: "mail", app: "Mail", title: "New Message", fields: [["To:", "Anna Weber"], ["Subject:", "Pitch deck feedback"]],
        text: "Hi Anna, thanks for the sharp notes on the deck. I'll rework the pricing slide and send it before Friday's call." },
      { kind: "slack", app: "Slack", title: "# product", from: "Lea", earlier: "Is the new onboarding ready for review?",
        text: "Yes, it's ready. Leave comments on anything that feels off and I'll fix it before tomorrow's release." },
      { kind: "terminal", app: "Terminal", title: "claude ~/hush", prompt: "claude",
        text: "Give every download demo its own app layout, keep the word count exact and run the blog tests." },
    ],
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
    readingTimeShort: (minutes: number) => `${minutes} Min.`,
    published: "Veröffentlicht",
    updated: "Aktualisiert",
    related: "Weiterlesen",
    allArticles: "Alle Artikel",
    readArticle: "Artikel lesen",
    topics: "Themen",
    allTopics: "Alle",
    editorialTitle: "Redaktionelle Richtlinien - hush Blog",
    editorialHeading: "Redaktionelle Richtlinien",
    editorialDescription: "Wie der hush Blog Artikel recherchiert, testet, schreibt und korrigiert: Primärquellen mit Datum, eigene Tests, geprüfter KI-Einsatz, keine Affiliate-Links.",
    writtenBy: "Geschrieben von",
    share: "Teilen",
    copyLink: "Link kopieren",
    linkCopied: "Link kopiert",
    shareOn: (network: string) => `Auf ${network} teilen`,
    shareByEmail: "Per E-Mail teilen",
    viewProfile: "Profil ansehen",
    authorDescription: (name: string) => `Artikel von ${name} zu Diktat, Spracherkennung und lokaler KI auf dem Mac, mit Hintergrund und Profilen.`,
    authorArticles: "Artikel",
    authorElsewhere: "Profile",
    ctaTitle: "Diktieren auf dem Mac, mit Modellen, die lokal laufen",
    ctaDownload: "Download für Mac",
    ctaMobile: "hush für den Mac holen",
    ctaDemos: [
      { kind: "mail", app: "Mail", title: "Neue E-Mail", fields: [["An:", "Anna Weber"], ["Betreff:", "Feedback zum Pitch Deck"]],
        text: "Hallo Anna, danke für die klaren Anmerkungen. Die überarbeitete Preisfolie kommt vor dem Termin am Freitag." },
      { kind: "slack", app: "Slack", title: "# produkt", from: "Lea", earlier: "Ist das neue Onboarding bereit für das Review?",
        text: "Ja, ist bereit. Anmerkungen bitte direkt als Kommentar, Korrekturen folgen vor dem Release morgen." },
      { kind: "terminal", app: "Terminal", title: "claude ~/hush", prompt: "claude",
        text: "Jede Download-Demo bekommt ein eigenes App-Layout, die Wortzahl bleibt exakt, danach die Blog-Tests ausführen." },
    ],
    ctaBody: "hush ist kostenlos und Open Source. Diktat und KI-Modelle laufen auf dem Mac; Websuche, Modell-Downloads, Updates und optionale Verified Messages nutzen das Internet.",
    by: "Von",
  },
} as const;
