// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The post-publish celebration, as in Ghost (apps/admin/src/editor/publish/
// celebration-handoff.ts and apps/admin/src/posts/list): publishing or
// scheduling in the editor writes a key and goes to the posts list, which reads
// it once, clears it in the same breath, and celebrates the post.

const keys = { published: "hush-last-published-post", scheduled: "hush-last-scheduled-post" } as const;

/** Reading `localStorage` can throw where storage is blocked. */
type StorageSource = () => Storage;
const browserStorage: StorageSource = () => window.localStorage;

export interface PublishCelebration {
  id: string;
  /** Whether it was published (rather than scheduled), which decides the copy. */
  wasPublished: boolean;
}

/** Written by the editor once the publish or schedule has landed. */
export function writePublishCelebration({ id, scheduled }: { id: string; scheduled: boolean }, storage: StorageSource = browserStorage) {
  try {
    storage().setItem(scheduled ? keys.scheduled : keys.published, JSON.stringify({ id }));
  } catch {
    // A full or blocked localStorage costs the celebration, not the publish.
  }
}

/**
 * Reads the handoff and clears both keys before anything is fetched: clearing
 * first costs at most one missed celebration, clearing later could repeat it on
 * every visit. A publish wins over a schedule.
 */
export function readPublishCelebration(storage: StorageSource = browserStorage): PublishCelebration | null {
  let published: string | null;
  let scheduled: string | null;
  try {
    const store = storage();
    published = store.getItem(keys.published);
    scheduled = store.getItem(keys.scheduled);
    store.removeItem(keys.published);
    store.removeItem(keys.scheduled);
  } catch {
    return null;
  }
  const raw = published ?? scheduled;
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as { id?: unknown };
    return typeof parsed?.id === "string" && parsed.id ? { id: parsed.id, wasPublished: published !== null } : null;
  } catch {
    return null;
  }
}

/**
 * The celebration's two lines (Ghost's posts/list/post-celebration-copy.ts,
 * without pages and email): a schedule gets one, a publish two, the second
 * counting the published posts once the count is known.
 */
export function celebrationCopy({ wasPublished, postCount }: { wasPublished: boolean; postCount?: number }) {
  if (!wasPublished) return { primary: "All set!", secondary: "" };
  if (typeof postCount !== "number") return { primary: "Your post is published.", secondary: "Spread the word!" };
  return { primary: "Boom! It’s out there.", secondary: `That’s ${postCount.toLocaleString("en")} ${postCount === 1 ? "post" : "posts"} published.` };
}
