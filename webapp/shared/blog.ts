// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import type { BlogAuthorId } from "./authors.ts";

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
  author: BlogAuthorId;
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
    readArticle: "Read article",
    writtenBy: "Written by",
    authorDescription: (name: string) => `Articles by ${name} on dictation, speech-to-text and local AI on Mac, with background and profiles.`,
    authorArticles: "Articles",
    authorElsewhere: "Elsewhere",
    ctaTitle: "Dictate on your Mac, with models that run locally",
    ctaDownload: "Download for Mac",
    ctaMobile: "Get hush for Mac",
    // The download card replays one dictation; HUD labels match the app.
    // The download card replays one dictation per loop and switches examples.
    // App names and HUD labels match the app, which is in English.
    ctaDemos: [
      { app: "Mail", title: "New Message", fields: [["To:", "Anna Weber"], ["Subject:", "Pitch deck feedback"]],
        text: "Hi Anna, thanks for the sharp notes on the deck. I'll rework the pricing slide and send it before Friday's call." },
      { app: "Slack", title: "# product", fields: [],
        text: "Quick update: the onboarding flow is ready for review. If anything feels off, leave a comment and I'll fix it before tomorrow's release." },
      { app: "Notes", title: "Launch ideas", fields: [],
        text: "Open the launch post with the offline demo, show the real numbers from our test Mac, and keep the whole thing under six hundred words." },
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
    published: "Veröffentlicht",
    updated: "Aktualisiert",
    onThisPage: "Auf dieser Seite",
    related: "Weiterlesen",
    allArticles: "Alle Artikel",
    readArticle: "Artikel lesen",
    writtenBy: "Geschrieben von",
    authorDescription: (name: string) => `Artikel von ${name} zu Diktat, Spracherkennung und lokaler KI auf dem Mac, mit Hintergrund und Profilen.`,
    authorArticles: "Artikel",
    authorElsewhere: "Profile",
    ctaTitle: "Diktieren auf dem Mac, mit Modellen, die lokal laufen",
    ctaDownload: "Für den Mac laden",
    ctaMobile: "hush für den Mac holen",
    ctaDemos: [
      { app: "Mail", title: "Neue E-Mail", fields: [["An:", "Anna Weber"], ["Betreff:", "Feedback zum Pitch Deck"]],
        text: "Hallo Anna, danke für die klaren Anmerkungen. Die überarbeitete Preisfolie kommt vor dem Termin am Freitag." },
      { app: "Slack", title: "# produkt", fields: [],
        text: "Kurzes Update: Das neue Onboarding ist bereit für das Review. Anmerkungen bitte direkt als Kommentar, Korrekturen folgen vor dem Release morgen." },
      { app: "Notes", title: "Ideen zum Launch", fields: [],
        text: "Den Launch-Beitrag mit der Offline-Demo eröffnen, echte Messwerte vom Test-Mac zeigen und unter sechshundert Wörtern bleiben." },
    ],
    ctaBody: "hush ist kostenlos und Open Source. Diktat und KI-Modelle laufen auf dem Mac; Websuche, Modell-Downloads, Updates und optionale Verified Messages nutzen das Internet.",
    by: "Von",
  },
} as const;
