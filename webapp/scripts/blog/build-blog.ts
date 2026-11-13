// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Reads Markdown articles, validates them against the hush blog contract and
// renders them to HTML. Pure apart from reading the content directory, so it
// can be tested against fixtures. The writer lives in generate-blog.ts.
import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import rehypeSlug from "rehype-slug";
import rehypeStringify from "rehype-stringify";
import remarkGfm from "remark-gfm";
import remarkParse from "remark-parse";
import remarkRehype from "remark-rehype";
import { unified } from "unified";
import { parse as parseYaml } from "yaml";
import { z } from "zod";

export const blogLanguages = ["en", "de"] as const;
export type BlogLanguage = (typeof blogLanguages)[number];

/** Front matter written by the hush-seo skill. Unknown fields fail loudly. */
export const frontMatterSchema = z.object({
  title: z.string().min(50).max(60),
  description: z.string().min(140).max(160),
  slug: z.string().regex(/^[a-z0-9]+(-[a-z0-9]+)*$/),
  lang: z.enum(blogLanguages),
  keyword: z.string().min(2),
  secondaryKeywords: z.array(z.string().min(2)).max(8),
  type: z.enum(["how-to", "comparison", "guide", "listicle", "news"]),
  cluster: z.string().min(2),
  author: z.string().min(2),
  authorUrl: z.url().startsWith("https://"),
  published: z.iso.date(),
  updated: z.iso.date(),
  imageAlt: z.string().min(10).max(160),
  schema: z.tuple([z.literal("BlogPosting")]),
  draft: z.boolean(),
}).strict().refine((data) => data.updated >= data.published, {
  message: "updated must not be earlier than published",
  path: ["updated"],
});

export type FrontMatter = z.infer<typeof frontMatterSchema>;

export type TocEntry = { id: string; text: string };

export type BlogPost = {
  slug: string;
  lang: BlogLanguage;
  path: string;
  title: string;
  description: string;
  heading: string;
  type: FrontMatter["type"];
  cluster: string;
  author: string;
  authorUrl: string;
  published: string;
  updated: string;
  imageAlt: string;
  readingMinutes: number;
  toc: TocEntry[];
  html: string;
  /** Internal only: used for duplicate checks, never rendered. */
  keyword: string;
};

const faqHeadings: Record<BlogLanguage, string> = {
  en: "Frequently asked questions",
  de: "Häufige Fragen",
};

// Mirrors the hush-seo skill profile (section 4). Matched case-insensitively.
const bannedPhrases: Record<BlogLanguage, string[]> = {
  en: ["revolutionary", "game-changer", "game changer", "100% offline", "completely private",
    "no data ever leaves your mac", "supercharge", "seamless", "in today's fast-paced world",
    "free forever", "gdpr certified", "hipaa compliant"],
  de: ["revolutionär", "bahnbrechend", "100 % offline", "100% offline", "absolut sicher",
    "dsgvo-zertifiziert", "dsgvo zertifiziert"],
};

export function blogPath(lang: BlogLanguage, slug?: string) {
  const base = lang === "de" ? "/de/blog" : "/blog";
  return slug ? `${base}/${slug}` : base;
}

type MdNode = { type: string; depth?: number; url?: string; value?: string; children?: MdNode[] };
type HastNode = { type: string; tagName?: string; properties?: { id?: string }; value?: string; children?: HastNode[] };

function walk<T extends { children?: T[] }>(node: T, visit: (node: T) => void) {
  visit(node);
  for (const child of node.children ?? []) walk(child, visit);
}

function text(node: MdNode | HastNode): string {
  if (node.type === "text" || node.type === "inlineCode") return node.value ?? "";
  return (node.children ?? []).map((child) => text(child as MdNode)).join("");
}

export function splitFrontMatter(source: string) {
  const match = /^---\n([\s\S]*?)\n---\n?([\s\S]*)$/.exec(source.replace(/\r\n/g, "\n"));
  if (!match) throw new Error("missing front matter block delimited by ---");
  return { data: parseYaml(match[1]!) as unknown, body: match[2]! };
}

function isAllowedUrl(url: string) {
  if (url.startsWith("#")) return true;
  if (url.startsWith("/") && !url.startsWith("//")) return true;
  return /^(https:|mailto:)/i.test(url);
}

export type BuildResult = { posts: BlogPost[]; errors: string[] };

/**
 * @param contentDir directory with one subdirectory per language (en, de)
 * @param staticPaths existing non-blog site paths that articles may link to
 */
export async function buildBlog(contentDir: string, staticPaths: Iterable<string>): Promise<BuildResult> {
  const errors: string[] = [];
  const parsed: Array<{ file: string; front: FrontMatter; tree: MdNode; body: string }> = [];

  for (const lang of blogLanguages) {
    let files: string[] = [];
    try {
      files = (await readdir(join(contentDir, lang))).filter((file) => file.endsWith(".md")).sort();
    } catch {
      continue;
    }
    for (const file of files) {
      const where = `${lang}/${file}`;
      let source: string;
      try {
        source = await readFile(join(contentDir, lang, file), "utf8");
      } catch (error) {
        errors.push(`${where}: cannot read (${(error as Error).message})`);
        continue;
      }
      let split;
      try {
        split = splitFrontMatter(source);
      } catch (error) {
        errors.push(`${where}: ${(error as Error).message}`);
        continue;
      }
      const result = frontMatterSchema.safeParse(split.data);
      if (!result.success) {
        for (const issue of result.error.issues) {
          errors.push(`${where}: front matter ${issue.path.join(".") || "(root)"}: ${issue.message}`);
        }
        continue;
      }
      const front = result.data;
      if (front.lang !== lang) errors.push(`${where}: lang "${front.lang}" does not match its folder "${lang}"`);
      if (file !== `${front.slug}.md`) errors.push(`${where}: file name must be ${front.slug}.md`);
      if (front.draft) continue;
      const tree = unified().use(remarkParse).use(remarkGfm).parse(split.body) as unknown as MdNode;
      parsed.push({ file: where, front, tree, body: split.body });
    }
  }

  // Paths each language may link to: its own published articles and index,
  // plus the existing site pages.
  const knownPaths = new Set(staticPaths);
  for (const { front } of parsed) {
    knownPaths.add(blogPath(front.lang, front.slug));
    knownPaths.add(blogPath(front.lang));
  }

  const keywords = new Map<string, string>();
  const slugs = new Map<string, string>();
  const posts: BlogPost[] = [];

  for (const { file, front, tree, body } of parsed) {
    const lang = front.lang;
    const problems: string[] = [];

    const slugKey = `${lang}:${front.slug}`;
    if (slugs.has(slugKey)) problems.push(`slug already used by ${slugs.get(slugKey)}`);
    slugs.set(slugKey, file);
    const keywordKey = `${lang}:${front.keyword.toLowerCase().trim()}`;
    if (keywords.has(keywordKey)) problems.push(`keyword "${front.keyword}" already targeted by ${keywords.get(keywordKey)}`);
    keywords.set(keywordKey, file);

    const headings: Array<{ depth: number; text: string }> = [];
    walk(tree, (node) => {
      if (node.type === "heading") headings.push({ depth: node.depth!, text: text(node) });
      if (node.type === "link") {
        const url = node.url ?? "";
        if (!isAllowedUrl(url)) problems.push(`link "${url}" must be https:, mailto:, a site path or #anchor`);
        else if (url.startsWith("/")) {
          const path = url.split(/[?#]/)[0]!.replace(/\/$/, "") || "/";
          const otherLanguage = lang === "en" ? path.startsWith("/de/blog") : path.startsWith("/blog");
          if (otherLanguage) problems.push(`internal link ${url} points to the other language's blog`);
          else if (!knownPaths.has(path)) problems.push(`internal link ${url} does not resolve to a published page`);
        }
      }
      if (node.type === "html") problems.push("raw HTML is not allowed in articles");
    });

    const h1 = headings.filter((heading) => heading.depth === 1);
    if (h1.length !== 1) problems.push(`must contain exactly one H1, found ${h1.length}`);
    if (headings[0] && headings[0].depth !== 1) problems.push("the first heading must be the H1");
    for (let index = 1; index < headings.length; index++) {
      if (headings[index]!.depth > headings[index - 1]!.depth + 1) {
        problems.push(`heading "${headings[index]!.text}" skips a level`);
      }
    }
    if (!headings.some((heading) => heading.depth === 2 && heading.text.trim() === faqHeadings[lang])) {
      problems.push(`missing the "## ${faqHeadings[lang]}" section`);
    }
    const prose = `${front.title}\n${front.description}\n${body}`;
    if (prose.includes("\u2014")) problems.push("contains an em dash; use commas or periods");
    const lower = prose.toLowerCase();
    for (const phrase of bannedPhrases[lang]) {
      if (lower.includes(phrase)) problems.push(`contains the banned phrase "${phrase}"`);
    }

    if (problems.length) {
      errors.push(...problems.map((problem) => `${file}: ${problem}`));
      continue;
    }

    const hast = await unified()
      .use(remarkRehype)
      .use(rehypeSlug)
      .run(tree as never) as unknown as HastNode;
    // The page renders the H1 in its own header with the byline, so remove it
    // from the body to keep exactly one H1 on the page.
    let heading = "";
    const toc: TocEntry[] = [];
    hast.children = (hast.children ?? []).filter((node) => {
      if (node.type === "element" && node.tagName === "h1") {
        heading = text(node);
        return false;
      }
      return true;
    });
    walk(hast, (node) => {
      if (node.type === "element" && node.tagName === "h2" && node.properties?.id) {
        toc.push({ id: String(node.properties.id), text: text(node) });
      }
    });
    const html = unified().use(rehypeStringify).stringify(hast as never);
    const words = body.split(/\s+/).filter(Boolean).length;

    posts.push({
      slug: front.slug,
      lang,
      path: blogPath(lang, front.slug),
      title: front.title,
      description: front.description,
      heading,
      type: front.type,
      cluster: front.cluster,
      author: front.author,
      authorUrl: front.authorUrl,
      published: front.published,
      updated: front.updated,
      imageAlt: front.imageAlt,
      readingMinutes: Math.max(1, Math.round(words / 220)),
      toc,
      html,
      keyword: front.keyword,
    });
  }

  posts.sort((a, b) => b.published.localeCompare(a.published) || a.slug.localeCompare(b.slug));
  return { posts, errors };
}
