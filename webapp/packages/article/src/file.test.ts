// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { describe, expect, test } from "bun:test";
import { articleContent, formatArticle, parseArticle, readDraftContent, type FrontMatter } from "./file.ts";

const front: FrontMatter = {
  title: "Dictate on a Mac without the cloud: a step-by-step guide",
  description: "How to dictate on a Mac with speech recognition that runs on the device, so your words never leave it, set up in a few minutes with free tools and no account.",
  slug: "dictate-without-cloud", lang: "en", keyword: "dictate without cloud", secondaryKeywords: ["offline dictation"],
  type: "how-to", cluster: "local-ai", author: "clemens-kressmann", published: "2026-11-01", updated: "2026-11-02",
  imageAlt: "A Mac with a microphone icon", schema: ["BlogPosting"], draft: false,
};

describe("the article file format", () => {
  test("an article round-trips through formatArticle and parseArticle", () => {
    const source = formatArticle({ front, body: "# Dictate on a Mac\n\nText.\n" });
    expect(parseArticle(source)).toEqual({ article: { front, body: "# Dictate on a Mac\n\nText.\n" }, problems: [] });
  });

  test("articleContent keeps the content and drops the lifecycle keys", () => {
    const content = articleContent({ front, body: "Body" });
    expect(content).toEqual({
      title: front.title, description: front.description, slug: front.slug, lang: "en", keyword: front.keyword,
      secondaryKeywords: front.secondaryKeywords, type: "how-to", cluster: front.cluster, author: front.author,
      imageAlt: front.imageAlt, markdown: "Body",
    });
  });

  test("readDraftContent accepts an incomplete draft and ignores its lifecycle keys", () => {
    const { content, problems } = readDraftContent("---\ntitle: Short\nslug: wip\ndraft: false\npublished: 2026-01-01\n---\n# Wip\n");
    expect(problems).toEqual([]);
    expect(content).toEqual({ title: "Short", slug: "wip", markdown: "# Wip\n" });
  });

  test("readDraftContent refuses unknown fields and a missing front matter block", () => {
    expect(readDraftContent("---\ntitel: Typo\n---\nBody").problems).toEqual(["front matter titel: unknown field"]);
    expect(readDraftContent("# No front matter").problems).toEqual(["missing front matter block delimited by ---"]);
    expect(readDraftContent("---\n- a list\n---\nBody").problems).toEqual(["front matter must be a list of fields"]);
  });
});
