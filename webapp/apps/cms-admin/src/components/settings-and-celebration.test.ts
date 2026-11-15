// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The rules behind the docked settings panel and the publish celebration
// (CMS-009, CMS-010): what the browser remembers, what the celebration says and
// where it links.
import { describe, expect, test } from "bun:test";
import { articleUrl, articleUrlPreview } from "@/lib/article-url";
import { celebrationCopy, readPublishCelebration, writePublishCelebration } from "./publish-celebration";
import { readSettingsOpen, settingsOpenAtStart, settingsOpenKey, writeSettingsOpen } from "./settings-open";

/** A Storage over a Map, and one that refuses every access, as a blocked localStorage does. */
function memoryStorage() {
  const map = new Map<string, string>();
  const storage = {
    getItem: (key: string) => map.get(key) ?? null,
    setItem: (key: string, value: string) => void map.set(key, value),
    removeItem: (key: string) => void map.delete(key),
    clear: () => map.clear(),
    key: () => null,
    get length() { return map.size; },
  } as Storage;
  return { map, source: () => storage };
}
const blocked = () => { throw new Error("SecurityError"); };

describe("article URLs", () => {
  test("an English post lives under /blog, a German one under /de/blog", () => {
    expect(articleUrl("en", "local-dictation")).toBe("https://behu.sh/blog/local-dictation");
    expect(articleUrl("de", "diktieren-ohne-cloud")).toBe("https://behu.sh/de/blog/diktieren-ohne-cloud");
    expect(articleUrlPreview("de", "diktieren")).toBe("behu.sh/de/blog/diktieren");
    expect(articleUrlPreview("en", "")).toBe("behu.sh/blog/…");
  });
});

describe("the settings panel's memory", () => {
  test("remembers the last toggle and reads anything else as closed", () => {
    const { map, source } = memoryStorage();
    expect(readSettingsOpen(source)).toBe(false);
    writeSettingsOpen(true, source);
    expect(map.get(settingsOpenKey)).toBe("open");
    expect(readSettingsOpen(source)).toBe(true);
    writeSettingsOpen(false, source);
    expect(readSettingsOpen(source)).toBe(false);
    map.set(settingsOpenKey, "maybe");
    expect(readSettingsOpen(source)).toBe(false);
  });

  test("blocked storage starts the panel closed and costs only the memory", () => {
    expect(readSettingsOpen(blocked)).toBe(false);
    expect(() => writeSettingsOpen(true, blocked)).not.toThrow();
  });

  test("where the panel would cover the post it always starts closed", () => {
    expect(settingsOpenAtStart({ overlay: false, stored: true })).toBe(true);
    expect(settingsOpenAtStart({ overlay: true, stored: true })).toBe(false);
    expect(settingsOpenAtStart({ overlay: false, stored: false })).toBe(false);
  });
});

describe("the publish celebration", () => {
  test("is read once: reading clears both keys, and a publish wins over a schedule", () => {
    const { map, source } = memoryStorage();
    writePublishCelebration({ id: "a", scheduled: true }, source);
    writePublishCelebration({ id: "b", scheduled: false }, source);
    expect(readPublishCelebration(source)).toEqual({ id: "b", wasPublished: true });
    expect(map.size).toBe(0);
    expect(readPublishCelebration(source)).toBeNull();
  });

  test("a schedule celebrates as not yet published", () => {
    const { source } = memoryStorage();
    writePublishCelebration({ id: "a", scheduled: true }, source);
    expect(readPublishCelebration(source)).toEqual({ id: "a", wasPublished: false });
  });

  test("a damaged key or blocked storage celebrates nothing and never throws", () => {
    const { map, source } = memoryStorage();
    map.set("hush-last-published-post", "{not json");
    expect(readPublishCelebration(source)).toBeNull();
    expect(map.size).toBe(0);
    map.set("hush-last-published-post", JSON.stringify({ id: "" }));
    expect(readPublishCelebration(source)).toBeNull();
    expect(readPublishCelebration(blocked)).toBeNull();
    expect(() => writePublishCelebration({ id: "a", scheduled: false }, blocked)).not.toThrow();
  });

  test("says what Ghost says", () => {
    expect(celebrationCopy({ wasPublished: false })).toEqual({ primary: "All set!", secondary: "" });
    expect(celebrationCopy({ wasPublished: true })).toEqual({ primary: "Your post is published.", secondary: "Spread the word!" });
    expect(celebrationCopy({ wasPublished: true, postCount: 1 })).toEqual({ primary: "Boom! It’s out there.", secondary: "That’s 1 post published." });
    expect(celebrationCopy({ wasPublished: true, postCount: 1234 })).toEqual({ primary: "Boom! It’s out there.", secondary: "That’s 1,234 posts published." });
  });
});
