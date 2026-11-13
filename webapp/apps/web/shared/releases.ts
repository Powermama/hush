export type ReleaseVisibility = "private" | "public";

export type ReleaseSection = {
  label: "Added" | "Improved" | "Fixed";
  items: readonly {
    title: string;
    detail: string;
  }[];
};

export type HushRelease = {
  slug: string;
  version: string;
  displayVersion: string;
  build: number;
  releasedAt: string;
  displayDate: string;
  channel: string;
  visibility: ReleaseVisibility;
  title: string;
  summary: string;
  downloadURL: string;
  downloadName: string;
  systemRequirements: string;
  sections: readonly ReleaseSection[];
  knownNotes: readonly string[];
};

// Add a release only after its immutable download is published and verified.
// Older unnotarized builds have been withdrawn from the website.
export const releases: readonly HushRelease[] = [
  {
    slug: "0.1.0-alpha.5",
    version: "0.1.0-alpha.5",
    displayVersion: "0.1 alpha 5",
    build: 14,
    releasedAt: "2026-11-04",
    displayDate: "4 November 2026",
    channel: "Private alpha",
    visibility: "private",
    title: "A clearer first step.",
    summary:
      "A small update to the way hush arrives on your Mac: a clear drag-and-drop installer, with Developer ID signing and Apple notarization.",
    downloadURL:
      "https://updates.behu.sh/downloads/hush-0.1.0-alpha.5-build.14.dmg",
    downloadName: "hush-0.1.0-alpha.5-build.14.dmg",
    systemRequirements: "Apple silicon and macOS 15 or later",
    sections: [
      {
        label: "Fixed",
        items: [
          {
            title: "Drag, drop, and you're home",
            detail:
              "The installer now opens at the right size, with hush, an arrow, and your Applications folder in place. Drag hush across, then open it from Applications.",
          },
        ],
      },
    ],
    knownNotes: [
      "macOS may ask you to approve the first launch and name Safari as the download source. This is a normal security prompt; no Terminal command is needed.",
      "This is still an early alpha. I'm working toward a full public release, and I'd like to open-source the app in the future.",
      "Built for Macs with Apple silicon. We recommend 16 GB of memory for the optional assistant; it is not a requirement for core dictation.",
    ],
  },
  {
    slug: "0.1.0-alpha.4",
    version: "0.1.0-alpha.4",
    displayVersion: "0.1 alpha 4",
    build: 13,
    releasedAt: "2026-11-04",
    displayDate: "4 November 2026",
    channel: "Private alpha",
    visibility: "private",
    title: "Our first notarized alpha.",
    summary:
      "A small milestone for hush: the first alpha notarized by Apple. I'm working toward a full public release, and I'd like to open-source the app in the future.",
    downloadURL:
      "https://updates.behu.sh/downloads/hush-0.1.0-alpha.4-build.13.dmg",
    downloadName: "hush-0.1.0-alpha.4-build.13.dmg",
    systemRequirements: "Apple silicon and macOS 15 or later",
    sections: [
      {
        label: "Improved",
        items: [
          {
            title: "A simpler installation",
            detail:
              "The app and download are signed with Developer ID and notarized by Apple. Open the DMG, move hush to Applications, and launch it normally. No Terminal workaround is needed.",
          },
          {
            title: "Ready for offline checks",
            detail:
              "Apple's notarization ticket is included with the download, so macOS can verify it even without an internet connection.",
          },
        ],
      },
      {
        label: "Fixed",
        items: [
          {
            title: "Typing measurement freeze",
            detail:
              "Fixed a loop that could make hush unresponsive when everyday typing measurement was turned off or Accessibility permission was revoked.",
          },
          {
            title: "Listening across desktops",
            detail:
              "The listening indicator now refreshes when Spaces or displays change, and its timer stops when it is hidden.",
          },
        ],
      },
    ],
    knownNotes: [
      "This is still an early alpha. Features and behavior will continue to improve before the full public release.",
      "Built for Macs with Apple silicon. We recommend 16 GB of memory for the optional assistant; it is not a requirement for core dictation.",
      "Speech and writing models run on your Mac. Some models need an initial download before offline use.",
    ],
  },
];

export const latestRelease: HushRelease | undefined = releases.at(0);

export function releasePath(release: HushRelease) {
  return `/releases/${release.slug}`;
}

export function findRelease(slug: string) {
  return releases.find((release) => release.slug === slug);
}
