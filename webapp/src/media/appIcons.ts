// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import mail from "./app-icons/mail.png?url";
import messages from "./app-icons/messages.png?url";
import slack from "./app-icons/slack.png?url";
import notion from "./app-icons/notion.png?url";
import notes from "./app-icons/notes.png?url";
import figma from "./app-icons/figma.png?url";
import chrome from "./app-icons/chrome.png?url";

export const appIcons: Readonly<Partial<Record<string, string>>> = {
  Mail: mail,
  Messages: messages,
  Slack: slack,
  Notion: notion,
  Notes: notes,
  Figma: figma,
  Chrome: chrome,
};
