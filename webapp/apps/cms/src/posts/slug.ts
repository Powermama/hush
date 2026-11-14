// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The address of a draft that was not given one: taken from its heading, as
// "untitled" until it has one, and numbered when another post of the language
// already uses it.

/** The slug of a post that has no heading yet; such a draft takes its slug from the heading it gets. */
export const untitledSlug = "untitled";
export const isUntitled = (slug: string) => /^untitled(-\d+)?$/.test(slug);

const transliterated: Record<string, string> = { ä: "ae", ö: "oe", ü: "ue", ß: "ss" };

/** Lowercase words joined by dashes, with German umlauts written out and other accents dropped. */
export function slugify(text: string) {
  return text.toLowerCase()
    .replace(/[äöüß]/g, (letter) => transliterated[letter]!)
    .normalize("NFKD").replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
    .slice(0, 80).replace(/-+$/, "");
}

/** The slug a post's content suggests: its H1, else its SEO title, else "untitled". */
export function suggestedSlug({ markdown, title }: { markdown: string; title: string }) {
  const heading = /^#[ \t]+(.+)$/m.exec(markdown)?.[1] ?? "";
  return slugify(heading) || slugify(title) || untitledSlug;
}

/** The first of base, base-2, base-3 and so on that is not taken. */
export function freeSlug(base: string, taken: ReadonlySet<string>) {
  if (!taken.has(base)) return base;
  for (let number = 2; ; number++) if (!taken.has(`${base}-${number}`)) return `${base}-${number}`;
}
