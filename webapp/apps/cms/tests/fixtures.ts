// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { createSession, sessionCookie } from "../src/auth/sessions";
import type { Database } from "../src/db/client";
import type { PostFields } from "../src/posts/fields";

/** The owner signed in to the admin, as a session cookie: tokens are agents and need the owner's approval to go live. */
export async function ownerSession(db: Database) {
  const { token } = await createSession(db, { githubUserId: 1, githubLogin: "owner" });
  return `${sessionCookie}=${token}`;
}

/** Request headers for a credential: the owner's session cookie or a bearer token. */
export const credentials = (credential: string): Record<string, string> =>
  credential.startsWith(`${sessionCookie}=`) ? { cookie: credential } : { authorization: `Bearer ${credential}` };

/** A draft that meets the article contract. */
export function validPost(overrides: Partial<PostFields> = {}): PostFields {
  return {
    lang: "en",
    slug: "dictate-without-cloud",
    title: "How to dictate on a Mac without the cloud, step by step",
    description: "A practical guide to dictating on a Mac with speech models that run locally, what still needs the internet, and how to set everything up in minutes.",
    keyword: "dictate without cloud",
    secondaryKeywords: ["offline dictation mac", "local speech to text"],
    type: "how-to",
    cluster: "local-dictation",
    author: "clemens-kressmann",
    imageAlt: "A Mac with a dictation waveform.",
    markdown: [
      "# How to dictate on a Mac without the cloud",
      "",
      "Local dictation keeps your voice on your Mac. Read more on [the home page](/).",
      "",
      "## How does it work?",
      "",
      "The speech model runs on your Mac.",
      "",
      "## Frequently asked questions",
      "",
      "### Does it need the internet?",
      "",
      "Only to download the model once.",
    ].join("\n"),
    ...overrides,
  };
}
