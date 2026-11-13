// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import type { PostFields } from "../src/posts/fields";

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
