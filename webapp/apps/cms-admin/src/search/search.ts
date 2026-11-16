// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// What Cmd/Ctrl+K finds, as Ghost Admin's global search does
// (apps/admin/src/global-search: search-source.ts, search-providers.ts,
// content-sources.ts, search-shortcut.ts): groups of results, posts first by
// status, each group capped. Posts are English and German, so matching is
// Ghost's basic provider (case-insensitive substrings, which suit any
// language), required for every word of the term, in any order.

export type SearchItem =
  | { kind: "navigate"; id: string; title: string; keywords?: string; status?: string; to: string; params?: Record<string, string> }
  | { kind: "action"; id: string; title: string; keywords?: string; status?: string; run: () => void };

export type SearchSource = { id: string; heading: string; items: readonly SearchItem[]; compare?: (a: SearchItem, b: SearchItem) => number };
export type SearchResultGroup = { id: string; heading: string; items: SearchItem[] };

// Every option is rendered, so each group is capped.
const resultLimit = 100;

/** Scheduled, then draft, then published, as Ghost lists them. */
const statusPriority: Record<string, number> = { scheduled: 1, draft: 2, published: 3 };
export const compareByStatus = (a: SearchItem, b: SearchItem) => (statusPriority[a.status ?? ""] ?? 5) - (statusPriority[b.status ?? ""] ?? 5);

export function search(sources: readonly SearchSource[], term: string): SearchResultGroup[] {
  const words = term.toLowerCase().split(/\s+/).filter(Boolean);
  if (!words.length) return [];
  return sources.flatMap((source) => {
    const matches = source.items.filter((item) => {
      const text = `${item.title} ${item.keywords ?? ""}`.toLowerCase();
      return words.every((word) => text.includes(word));
    });
    const items = (source.compare ? [...matches].sort(source.compare) : matches).slice(0, resultLimit);
    return items.length ? [{ id: source.id, heading: source.heading, items }] : [];
  });
}

export const isMac = typeof navigator !== "undefined" && /Mac|iPhone|iPad/.test(navigator.platform);
export const searchShortcutLabel = isMac ? "⌘K" : "Ctrl+K";

/** Cmd+K on a Mac, Ctrl+K elsewhere, with no other modifier. */
export function isSearchShortcut(event: KeyboardEvent, mac = isMac) {
  const modifier = mac ? event.metaKey : event.ctrlKey;
  const otherModifier = mac ? event.ctrlKey : event.metaKey;
  if (!modifier || otherModifier || event.altKey || event.shiftKey || event.isComposing) return false;
  // Autofill sends keydown events without a key.
  const key = typeof event.key === "string" ? event.key.toLowerCase() : "";
  // The physical K key counts only when its layout types a non-Latin character.
  return key === "k" || (!/^[a-z]$/.test(key) && event.code === "KeyK");
}
