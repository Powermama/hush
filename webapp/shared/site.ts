// SPDX-License-Identifier: AGPL-3.0-only
// Copyright 2026 Clemens Kressmann
import { legalConfig } from "./legal.ts";
import { releases, releasePath } from "./releases.ts";

export const siteOrigin = "https://behu.sh";
export type PageMetadata = {
  title: string;
  description: string;
  canonicalPath: string;
  indexable: boolean;
  language: "en" | "de";
  alternatePaths?: { en: string; de: string };
  modified?: string;
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
