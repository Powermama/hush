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
    slug: "0.1.0-alpha.9",
    version: "0.1.0-alpha.9",
    displayVersion: "0.1 alpha 9",
    build: 18,
    releasedAt: "2026-11-21",
    displayDate: "21 November 2026",
    channel: "Private alpha",
    visibility: "private",
    title: "Off means off.",
    summary:
      "When you switch the assistant off, ⌃ Fn no longer starts it, and local AI models leave your Mac's memory while nothing switched on uses them.",
    downloadURL:
      "https://updates.behu.sh/downloads/hush-0.1.0-alpha.9-build.18.dmg",
    downloadName: "hush-0.1.0-alpha.9-build.18.dmg",
    systemRequirements: "Apple silicon and macOS 15 or later",
    sections: [
      {
        label: "Improved",
        items: [
          {
            title: "hush uses less memory",
            detail:
              "A local AI model stays loaded only while Live Write or the assistant uses it, and the assistant's voice is released when you switch the assistant off.",
          },
        ],
      },
      {
        label: "Fixed",
        items: [
          {
            title: "The assistant switch",
            detail:
              "With the assistant switched off, ⌃ Fn shows that it is off instead of starting it, and switching it off ends a conversation that is still running.",
          },
          {
            title: "hush in lowercase",
            detail: "The app writes its name as hush everywhere.",
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
    slug: "0.1.0-alpha.8",
    version: "0.1.0-alpha.8",
    displayVersion: "0.1 alpha 8",
    build: 17,
    releasedAt: "2026-11-20",
    displayDate: "20 November 2026",
    channel: "Private alpha",
    visibility: "private",
    title: "An honest assistant.",
    summary:
      "The assistant now tells you it is an AI and talks in English, ⌃ Fn works when it uses your ChatGPT plan, and the recognition boost shows how far its download is.",
    downloadURL:
      "https://updates.behu.sh/downloads/hush-0.1.0-alpha.8-build.17.dmg",
    downloadName: "hush-0.1.0-alpha.8-build.17.dmg",
    systemRequirements: "Apple silicon and macOS 15 or later",
    sections: [
      {
        label: "Added",
        items: [
          {
            title: "The assistant says it is an AI",
            detail:
              "An AI label sits next to its status, VoiceOver names it as hush's AI assistant, and the first spoken reply of each conversation says so.",
          },
          {
            title: "Download progress for the recognition boost",
            detail:
              "The boost download shows its progress in percent and megabytes, and you can stop it.",
          },
        ],
      },
      {
        label: "Improved",
        items: [
          {
            title: "The assistant talks in English",
            detail:
              "Its voice speaks English, so its replies are in English too. Text it writes into your apps keeps the language you ask for.",
          },
        ],
      },
      {
        label: "Fixed",
        items: [
          {
            title: "⌃ Fn with ChatGPT",
            detail:
              "With ChatGPT chosen as the assistant's AI model, ⌃ Fn starts the assistant instead of opening its settings.",
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
    slug: "0.1.0-alpha.7",
    version: "0.1.0-alpha.7",
    displayVersion: "0.1 alpha 7",
    build: 16,
    releasedAt: "2026-11-19",
    displayDate: "19 November 2026",
    channel: "Private alpha",
    visibility: "private",
    title: "Your words, written your way.",
    summary:
      "Teach hush the names and terms it gets wrong, keep Live Write out of the apps where your words should go in as spoken, and never lose a long dictation again.",
    downloadURL:
      "https://updates.behu.sh/downloads/hush-0.1.0-alpha.7-build.16.dmg",
    downloadName: "hush-0.1.0-alpha.7-build.16.dmg",
    systemRequirements: "Apple silicon and macOS 15 or later",
    sections: [
      {
        label: "Added",
        items: [
          {
            title: "Vocabulary you teach by voice",
            detail:
              "Type a name or term the way you write it, then say it a few times. hush learns what it hears and writes your word from then on, with or without Live Write. With Parakeet you can add an optional recognition boost (97.5 MB) that helps it hear your words in new ways.",
          },
          {
            title: "Live Write stays out of the way where it should",
            detail:
              "In terminals, code editors, AI chats and password managers, your words go in exactly as spoken. The list includes their websites, and you can add, remove or reset apps and sites.",
          },
          {
            title: "Your own ChatGPT plan, if you want it",
            detail:
              "Live Write and the assistant write on your Mac by default. You can instead sign in with ChatGPT and turn it on per feature; hush says what is sent before anything leaves your Mac.",
          },
        ],
      },
      {
        label: "Improved",
        items: [
          {
            title: "Text appears sooner",
            detail:
              "With Parakeet, hush recognises speech while you talk, so less is left to do when you release the key.",
          },
          {
            title: "No more keychain prompts",
            detail:
              "Sign-ins and keys now live in the Mac's data protection keychain, so hush no longer asks for your password to use them.",
          },
        ],
      },
      {
        label: "Fixed",
        items: [
          {
            title: "Long dictations are kept",
            detail:
              "A dictation that reaches the two-minute limit is kept and inserted. If your Mac sleeps or hush quits while you talk, the recording is recovered into History at the next launch.",
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
    slug: "0.1.0-alpha.6",
    version: "0.1.0-alpha.6",
    displayVersion: "0.1 alpha 6",
    build: 15,
    releasedAt: "2026-11-16",
    displayDate: "16 November 2026",
    channel: "Private alpha",
    visibility: "private",
    title: "Personas, in any light.",
    summary:
      "A fix for the persona editor: it now follows your Mac's appearance the moment you switch between Light and Dark.",
    downloadURL:
      "https://updates.behu.sh/downloads/hush-0.1.0-alpha.6-build.15.dmg",
    downloadName: "hush-0.1.0-alpha.6-build.15.dmg",
    systemRequirements: "Apple silicon and macOS 15 or later",
    sections: [
      {
        label: "Fixed",
        items: [
          {
            title: "Your instructions stay readable",
            detail:
              "Switching between Light and Dark while hush was open could leave the persona editor in the old colors, so its instructions looked empty and typing seemed not to work until hush was reopened. The editor and the shortcut fields now redraw as soon as you switch.",
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

/**
 * Where download buttons point: the website counts the download (PRD R10,
 * "downloads" means a download started) and redirects to the latest release's
 * exact immutable DMG. `from` is the path of the page the button is on.
 */
export function downloadPath(from: string) {
  return `/download?from=${encodeURIComponent(from)}`;
}
