// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { afterEach, describe, expect, test } from "bun:test";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import sharp from "sharp";
import { buildBlog } from "./build-blog";

const fixtures = join(import.meta.dir, "fixtures/content");
const staticPaths = ["/", "/verified-messages", "/releases"];

const front = {
  title: "\"How to dictate on a Mac without the cloud, step by step\"",
  description: "\"A practical guide to dictating on a Mac with speech models that run locally, what still needs the internet, and how to set everything up in minutes.\"",
  slug: "dictate-without-cloud",
  lang: "en",
  keyword: "dictate without cloud",
  secondaryKeywords: "[]",
  type: "how-to",
  cluster: "local-dictation",
  author: "clemens-kressmann",
  published: "\"2026-11-01\"",
  updated: "\"2026-11-02\"",
  imageAlt: "A Mac with a dictation waveform.",
  schema: "[\"BlogPosting\"]",
  draft: "false",
};
const validBody = `# How to dictate on a Mac without the cloud

The answer comes first. See [Verified Messages](/verified-messages).

## What runs locally?

Text.

## Frequently asked questions

### Does it need the internet?

Only for downloads.
`;

function article(overrides: Partial<Record<keyof typeof front | string, string | null>> = {}, body = validBody) {
  const fields = { ...front, ...overrides };
  const yaml = Object.entries(fields).filter(([, value]) => value !== null).map(([key, value]) => `${key}: ${value}`).join("\n");
  return `---\n${yaml}\n---\n\n${body}`;
}

let dirs: string[] = [];
afterEach(async () => {
  for (const dir of dirs) await rm(dir, { recursive: true, force: true });
  dirs = [];
});

async function contentWith(files: Record<string, string | Buffer>) {
  const dir = await mkdtemp(join(tmpdir(), "hush-blog-"));
  dirs.push(dir);
  for (const [path, content] of Object.entries(files)) {
    await mkdir(join(dir, path, ".."), { recursive: true });
    await writeFile(join(dir, path), content);
  }
  return dir;
}

const screenshot = () => sharp({ create: { width: 900, height: 450, channels: 3, background: "#ffffff" } }).png().toBuffer();
const withImage = (markdown: string) => validBody.replace("Text.", markdown);

async function errorsFor(files: Record<string, string>) {
  return (await buildBlog(await contentWith(files), staticPaths)).errors.join("\n");
}

describe("blog content pipeline", () => {
  test("renders published fixtures, excludes drafts and builds a table of contents", async () => {
    const { posts, errors } = await buildBlog(fixtures, staticPaths);
    expect(errors).toEqual([]);
    // Newest first.
    expect(posts.map((post) => post.path)).toEqual([
      "/blog/fixture-dictation-commands",
      "/de/blog/fixture-diktieren-ohne-cloud",
      "/blog/fixture-dictation-without-cloud",
    ]);
    const first = posts.find((post) => post.slug === "fixture-dictation-without-cloud")!;
    expect(first.heading).toBe("Fixture article body heading");
    // The page renders the H1 itself; the body HTML must not contain another.
    expect(first.html).not.toContain("<h1");
    expect(first.html).toContain('<h2 id="how-does-the-fixture-render">');
    expect(first.toc.map((entry) => entry.id)).toEqual(["how-does-the-fixture-render", "frequently-asked-questions"]);
    expect(first.html).toContain('<h2 id="frequently-asked-questions" class="blog-appendix">');
    expect(first.html).toContain("<table>");
    expect(posts.some((post) => post.slug === "fixture-draft")).toBe(false);
  });

  test("accepts a valid article", async () => {
    expect(await errorsFor({ "en/dictate-without-cloud.md": article() })).toBe("");
  });

  test("requires a registered author id", async () => {
    expect(await errorsFor({ "en/dictate-without-cloud.md": article({ author: "Clemens Kressmann" }) })).toContain("front matter author");
  });

  test("rejects unknown front matter fields, such as the skill's German names", async () => {
    expect(await errorsFor({ "en/dictate-without-cloud.md": article({ autor: "X" }) })).toContain("autor");
  });

  test("enforces title and description lengths", async () => {
    const errors = await errorsFor({ "en/dictate-without-cloud.md": article({ title: "Too short", description: "Also too short." }) });
    expect(errors).toContain("front matter title");
    expect(errors).toContain("front matter description");
  });

  test("rejects an updated date before the published date", async () => {
    expect(await errorsFor({ "en/dictate-without-cloud.md": article({ updated: "\"2026-10-01\"" }) })).toContain("updated must not be earlier");
  });

  test("requires the file name to match the slug and the folder to match the language", async () => {
    const errors = await errorsFor({ "de/other-name.md": article() });
    expect(errors).toContain('lang "en" does not match its folder "de"');
    expect(errors).toContain("file name must be dictate-without-cloud.md");
  });

  test("requires exactly one H1, ordered headings and the FAQ section", async () => {
    const errors = await errorsFor({
      "en/dictate-without-cloud.md": article({}, "# One\n\n# Two\n\n#### Skipped\n\nText.\n"),
    });
    expect(errors).toContain("exactly one H1, found 2");
    expect(errors).toContain('heading "Skipped" skips a level');
    expect(errors).toContain('missing the "## Frequently asked questions" section');
  });

  test("uses the German FAQ heading for German articles", async () => {
    const german = article({ lang: "de" }).replace("## Frequently asked questions", "## Häufige Fragen");
    expect(await errorsFor({ "de/dictate-without-cloud.md": german })).toBe("");
  });

  test("rejects em dashes and banned phrases", async () => {
    const body = validBody.replace("The answer comes first.", "The answer \u2014 truly revolutionary.");
    const errors = await errorsFor({ "en/dictate-without-cloud.md": article({}, body) });
    expect(errors).toContain("em dash");
    expect(errors).toContain('banned phrase "revolutionary"');
  });

  test("rejects raw HTML and unsafe link schemes", async () => {
    const body = validBody.replace("The answer comes first.", "Links: [x](javascript:alert) and [y](http://example.com).\n\n<script>alert(1)</script>");
    const errors = await errorsFor({ "en/dictate-without-cloud.md": article({}, body) });
    expect(errors).toContain("raw HTML is not allowed");
    expect(errors).toContain('link "javascript:alert"');
    expect(errors).toContain('link "http://example.com"');
  });

  test("checks internal links and keeps them within one language", async () => {
    const body = validBody.replace("The answer comes first.", "[dead](/blog/missing) [german](/de/blog/irgendwas)");
    const errors = await errorsFor({ "en/dictate-without-cloud.md": article({}, body) });
    expect(errors).toContain("internal link /blog/missing does not resolve");
    expect(errors).toContain("points to the other language's blog");
  });

  test("rejects two articles of one language targeting the same keyword", async () => {
    const errors = await errorsFor({
      "en/dictate-without-cloud.md": article(),
      "en/second.md": article({ slug: "second" }),
    });
    expect(errors).toContain('keyword "dictate without cloud" already targeted');
  });

  test("allows the same keyword in different languages", async () => {
    const german = article({ lang: "de" }).replace("## Frequently asked questions", "## Häufige Fragen");
    expect(await errorsFor({ "en/dictate-without-cloud.md": article(), "de/dictate-without-cloud.md": german })).toBe("");
  });

  test("ignores drafts entirely, including their content problems", async () => {
    const { posts, errors } = await buildBlog(await contentWith({
      "en/dictate-without-cloud.md": article({ draft: "true" }, "# Broken \u2014 draft"),
    }), staticPaths);
    expect(errors).toEqual([]);
    expect(posts).toEqual([]);
  });

  test("renders a standalone image as a figure with responsive WebP sources", async () => {
    const { posts, errors } = await buildBlog(await contentWith({
      "en/dictate-without-cloud.md": article({}, withImage('![Keyboard settings with the Dictation section](media/dictate-without-cloud/settings.png "Our test Mac")')),
      "en/media/dictate-without-cloud/settings.png": await screenshot(),
    }), staticPaths);
    expect(errors).toEqual([]);
    const html = posts[0]!.html;
    expect(html).toContain("<figure><img");
    expect(html).toMatch(/srcset="\/blog\/media\/dictate-without-cloud-settings-[0-9a-f]{10}-680\.webp 680w, \/blog\/media\/dictate-without-cloud-settings-[0-9a-f]{10}-900\.webp 900w"/);
    expect(html).toContain('width="680" height="340"');
    expect(html).toContain('loading="lazy"');
    expect(html).toContain("<figcaption>Our test Mac");
    expect(html).toMatch(/href="\/blog\/media\/dictate-without-cloud-settings-[0-9a-f]{10}-900\.webp"/);
    expect(html).toContain('aria-label="Open full-size image (new tab): Keyboard settings with the Dictation section"');
    expect(html).toContain('target="_blank" rel="noopener"');
    expect(html).toContain("View full-size image</a></figcaption>");
    expect(posts[0]!.images.map((image) => image.width)).toEqual([680, 900]);
  });

  test("rejects missing images, missing alt text, wrong folders and inline images", async () => {
    const errors = (await buildBlog(await contentWith({
      "en/dictate-without-cloud.md": article({}, withImage([
        "![Keyboard settings](media/dictate-without-cloud/missing.png)",
        "![](media/dictate-without-cloud/settings.png)",
        "![Another article's image](media/other-article/settings.png)",
        "Inline ![Keyboard settings inline](media/dictate-without-cloud/settings.png) image.",
      ].join("\n\n"))),
      "en/media/dictate-without-cloud/settings.png": await screenshot(),
    }), staticPaths)).errors.join("\n");
    expect(errors).toContain('"media/dictate-without-cloud/missing.png" does not exist');
    expect(errors).toContain("needs alt text of 10 to 160 characters");
    expect(errors).toContain("must live in media/dictate-without-cloud/");
    expect(errors).toContain("an image must stand alone in its own paragraph");
  });

  test("versions social previews when the headline changes and separates languages", async () => {
    const en = article();
    const de = article({ lang: "de" }).replace("## Frequently asked questions", "## Häufige Fragen");
    const dir = await contentWith({ "en/dictate-without-cloud.md": en, "de/dictate-without-cloud.md": de });
    const first = await buildBlog(dir, staticPaths);
    expect(first.errors).toEqual([]);
    const english = first.posts.find(post => post.lang === "en")!;
    const german = first.posts.find(post => post.lang === "de")!;
    expect(english.cover.path).toMatch(/^\/blog\/covers\/dictate-without-cloud-[a-f0-9]{10}-social\.png$/);
    expect(english.cover.path).not.toBe(german.cover.path);
    expect((await buildBlog(dir, staticPaths)).posts).toEqual(first.posts);
    await writeFile(join(dir, "en/dictate-without-cloud.md"), en.replace("# How to dictate on a Mac without the cloud", "# Local dictation on a Mac, step by step"));
    const changed = await buildBlog(dir, staticPaths);
    expect(changed.errors).toEqual([]);
    expect(changed.posts.find(post => post.lang === "en")!.cover.path).not.toBe(english.cover.path);
    expect(changed.posts.find(post => post.lang === "de")!.cover.path).toBe(german.cover.path);
  });

  test("turns a [!TLDR] blockquote before the first section into the summary box", async () => {
    const body = validBody.replace("The answer comes first.", "The answer comes first.\n\n> [!TLDR]\n> - **Restart** the service.\n> - Pick the microphone.");
    const { posts, errors } = await buildBlog(await contentWith({ "en/dictate-without-cloud.md": article({}, body) }), staticPaths);
    expect(errors).toEqual([]);
    expect(posts[0]!.html).toContain('<aside class="blog-tldr" aria-label="In short"><p class="blog-tldr-title">In short</p>');
    expect(posts[0]!.html).toContain("<li><strong>Restart</strong> the service.</li>");
    expect(posts[0]!.html).not.toContain("[!TLDR]");
  });

  test("allows one [!TLDR] summary, only before the first section", async () => {
    const late = validBody.replace("Text.", "Text.\n\n> [!TLDR]\n> Late.").replace("The answer comes first.", "> [!TLDR]\n> Early.");
    const errors = (await buildBlog(await contentWith({ "en/dictate-without-cloud.md": article({}, late) }), staticPaths)).errors.join("\n");
    expect(errors).toContain("must come before the first section");
    expect(errors).toContain("only one [!TLDR] summary is allowed");
  });

  test("reserves the editorial policy slug in each language", async () => {
    const errors = await errorsFor({ "en/editorial-policy.md": article({ slug: "editorial-policy" }) });
    expect(errors).toContain('slug "editorial-policy" is reserved for the editorial policy');
  });
});
