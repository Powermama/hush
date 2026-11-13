// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import type { BlogAuthorId } from "./authors.ts";

export type BlogLanguage = "en" | "de";

/**
 * Topic clusters from the content strategy (hush-seo skill). Articles name one by
 * id; the label appears on covers and cards. Unknown ids fail the build.
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

export type BlogArticleType = "how-to" | "comparison" | "guide" | "listicle" | "essay" | "news";

/**
 * Long guides get the margin column with contents and sharing, as on Intercom,
 * AFFiNE and Ahrefs. Essays and news read as one calm column, as on Notion and
 * Linear, with sharing after the text.
 */
export function hasReadingSidebar(type: BlogArticleType) {
  return type !== "essay" && type !== "news";
}

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
    published: "Veröffentlicht",
    updated: "Aktualisiert",
    onThisPage: "Auf dieser Seite",
    related: "Weiterlesen",
    allArticles: "Alle Artikel",
    readArticle: "Artikel lesen",
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
    ctaDownload: "Für den Mac laden",
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
