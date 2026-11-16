// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { describe, expect, test } from "bun:test";
import { compareByStatus, isSearchShortcut, search, type SearchItem } from "./search";

const post = (id: string, title: string, status: string, keywords = ""): SearchItem => ({ kind: "navigate", id, title, status, keywords, to: "/posts/$id" });
const posts = { id: "posts", heading: "Posts", compare: compareByStatus, items: [
  post("1", "Dictation Not Working on Mac? Fixes by Symptom", "published", "dictation-not-working-on-mac"),
  post("2", "Diktieren am Mac ohne Cloud", "draft", "diktieren-ohne-cloud offline diktat"),
  post("3", "How to dictate on a Mac without the cloud", "scheduled", "dictate-without-cloud"),
] };

describe("global search", () => {
  test("finds every word of the term in the title or keywords, in any order, scheduled before drafts before published", () => {
    expect(search([posts], "mac dict").flatMap((group) => group.items.map((item) => item.id))).toEqual(["3", "1"]);
    expect(search([posts], "OFFLINE")[0]!.items.map((item) => item.id)).toEqual(["2"]);
    expect(search([posts], "  ")).toEqual([]);
    expect(search([posts], "nothing like this")).toEqual([]);
  });

  test("Cmd+K on a Mac and Ctrl+K elsewhere, with no other modifier", () => {
    const key = (init: KeyboardEventInit) => ({ key: "k", code: "KeyK", metaKey: false, ctrlKey: false, altKey: false, shiftKey: false, isComposing: false, ...init }) as KeyboardEvent;
    expect(isSearchShortcut(key({ metaKey: true }), true)).toBe(true);
    expect(isSearchShortcut(key({ ctrlKey: true }), true)).toBe(false);
    expect(isSearchShortcut(key({ ctrlKey: true }), false)).toBe(true);
    expect(isSearchShortcut(key({ metaKey: true, shiftKey: true }), true)).toBe(false);
    // A non-Latin layout still counts by the physical K key.
    expect(isSearchShortcut(key({ metaKey: true, key: "л" }), true)).toBe(true);
  });
});
