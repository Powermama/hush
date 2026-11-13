// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import mail from "./app-icons/mail.png?url";
import messages from "./app-icons/messages.png?url";
import slack from "./app-icons/slack.png?url";
import notion from "./app-icons/notion.png?url";
import notes from "./app-icons/notes.png?url";
import figma from "./app-icons/figma.png?url";
import chrome from "./app-icons/chrome.png?url";
import mailShadow from "./app-icons/mail-shadow.webp?no-inline";
import messagesShadow from "./app-icons/messages-shadow.webp?no-inline";
import slackShadow from "./app-icons/slack-shadow.webp?no-inline";
import notionShadow from "./app-icons/notion-shadow.webp?no-inline";
import notesShadow from "./app-icons/notes-shadow.webp?no-inline";
import figmaShadow from "./app-icons/figma-shadow.webp?no-inline";
import chromeShadow from "./app-icons/chrome-shadow.webp?no-inline";

export const appIcons: Readonly<Partial<Record<string, string>>> = {
  Mail: mail,
  Messages: messages,
  Slack: slack,
  Notion: notion,
  Notes: notes,
  Figma: figma,
  Chrome: chrome,
};

/** Hero icons with their soft shadow baked in by scripts/bake-artwork.mjs. */
export const shadowedAppIcons: Readonly<Partial<Record<string, string>>> = {
  Mail: mailShadow,
  Messages: messagesShadow,
  Slack: slackShadow,
  Notion: notionShadow,
  Notes: notesShadow,
  Figma: figmaShadow,
  Chrome: chromeShadow,
};
