// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Reads Markdown articles, validates them against the hush blog contract and
// renders them to HTML. Pure apart from reading the content directory, so it
// can be tested against fixtures. The writer lives in generate-blog.ts.
import { createHash } from "node:crypto";
import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import sharp from "sharp";
import rehypeSlug from "rehype-slug";
import rehypeStringify from "rehype-stringify";
import remarkGfm from "remark-gfm";
import remarkParse from "remark-parse";
import remarkRehype from "remark-rehype";
import { unified } from "unified";
import { parse as parseYaml } from "yaml";
import { z } from "zod";
import { authorPath, blogAuthorIds, type BlogAuthorId } from "../../shared/authors";
import { blogClusterIds, editorialPolicyPath, editorialPolicySlugs, type BlogClusterId } from "../../shared/blog";

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
  type: z.enum(["how-to", "comparison", "guide", "listicle", "essay", "news"]),
  cluster: z.enum(blogClusterIds),
  author: z.enum(blogAuthorIds),
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

/**
 * The cover of an article, rendered from cover-template.html. The hash covers the
 * template, renderer and every value shown, so changes produce new file names.
 */
export type BlogCoverPlan = {
  hash: string;
  lang: BlogLanguage;
  title: string;
  /** The 1200x630 PNG for link previews. */
  path: string;
  /** The same artwork as an 800px WebP for article cards. */
  cardPath: string;
};

export const coverTemplatePath = join(import.meta.dir, "cover-template.html");

/** One responsive rendition the generator writes to public/. */
export type BlogImageOutput = { source: string; path: string; width: number };

// Article images render at most 680 CSS px wide; the second size serves 2x screens.
const imageWidths = [680, 1360];
const imageSizes = "(min-width: 768px) 680px, calc(100vw - 40px)";
const imagePath = /^media\/([a-z0-9-]+)\/([a-z0-9-]+)\.(png|jpe?g|webp)$/;

export type BlogPost = {
  slug: string;
  lang: BlogLanguage;
  path: string;
  title: string;
  description: string;
  heading: string;
  type: FrontMatter["type"];
  cluster: BlogClusterId;
  author: BlogAuthorId;
  published: string;
  updated: string;
  imageAlt: string;
  readingMinutes: number;
  toc: TocEntry[];
  html: string;
  /** Internal only: used for duplicate checks, never rendered. */
  keyword: string;
  /** Internal only: image renditions the generator must write. */
  images: BlogImageOutput[];
  cover: BlogCoverPlan;
};

// A blockquote starting with [!TLDR] (GitHub alert syntax) becomes the summary box.
const tldrMarker = "[!TLDR]";
const tldrTitles: Record<BlogLanguage, string> = { en: "In short", de: "Kurz gesagt" };

function isTldr(node: { children?: Array<{ type: string; tagName?: string; children?: Array<{ type: string; value?: string }> }> }) {
  const first = node.children?.find((child) => child.type === "paragraph" || child.tagName === "p");
  const text = first?.children?.[0];
  return text?.type === "text" && (text.value ?? "").trimStart().startsWith(tldrMarker);
}

const copyLabels: Record<BlogLanguage, { label: string; text: string; copied: string }> = {
  en: { label: "Copy code", text: "Copy", copied: "Copied" },
  de: { label: "Code kopieren", text: "Kopieren", copied: "Kopiert" },
};

/** Wraps every code block with a copy button; the article page handles the click. */
function addCopyButtons(node: HastNode, lang: BlogLanguage) {
  node.children = node.children?.map((child) => {
    if (child.type !== "element" || child.tagName !== "pre") { addCopyButtons(child, lang); return child; }
    return {
      type: "element", tagName: "div", properties: { className: ["blog-code"] }, children: [child, {
        type: "element", tagName: "button", properties: { type: "button", className: ["blog-code-copy"], ariaLabel: copyLabels[lang].label, dataCopiedLabel: copyLabels[lang].copied },
        children: [{ type: "text", value: copyLabels[lang].text }],
      }],
    };
  });
}

const faqHeadings: Record<BlogLanguage, string> = {
  en: "Frequently asked questions",
  de: "Häufige Fragen",
};
// The FAQ and the sources section close the article; the page sets them apart from the body.
const sourcesHeadings: Record<BlogLanguage, string> = {
  en: "Sources and how we tested",
  de: "Quellen und Testaufbau",
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

type MdNode = { type: string; depth?: number; url?: string; alt?: string; title?: string | null; value?: string; children?: MdNode[] };
type HastNode = { type: string; tagName?: string; properties?: Record<string, unknown>; value?: string; children?: HastNode[] };

type ArticleImage = { url: string; alt: string; title?: string; width: number; height: number; renditions: BlogImageOutput[] };

/** Validates an article image and plans its WebP renditions. */
async function planImage(contentDir: string, lang: string, slug: string, node: MdNode, problems: string[]): Promise<ArticleImage | undefined> {
  const url = node.url ?? "";
  const match = imagePath.exec(url);
  if (!match) { problems.push(`image "${url}" must be media/${slug}/<name>.png|jpg|webp`); return; }
  if (match[1] !== slug) { problems.push(`image "${url}" must live in media/${slug}/`); return; }
  const alt = (node.alt ?? "").trim();
  if (alt.length < 10 || alt.length > 160) problems.push(`image "${url}" needs alt text of 10 to 160 characters`);
  const source = join(contentDir, lang, url);
  let bytes: Buffer;
  try { bytes = await readFile(source); } catch { problems.push(`image "${url}" does not exist`); return; }
  const { width, height } = await sharp(bytes).metadata();
  if (!width || !height) { problems.push(`image "${url}" cannot be read`); return; }
  if (width < imageWidths[0]!) problems.push(`image "${url}" is ${width}px wide; provide at least ${imageWidths[0]}px`);
  // Content-hashed names: a changed image gets new URLs, so caches never serve a stale one.
  const hash = createHash("sha256").update(bytes).digest("hex").slice(0, 10);
  const renditions = [...new Set(imageWidths.map((target) => Math.min(target, width)))].map((target) => ({
    source, width: target, path: `/blog/media/${slug}-${match[2]}-${hash}-${target}.webp`,
  }));
  return { url, alt, title: node.title ?? undefined, width, height, renditions };
}

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
  const coverTemplate = await readFile(coverTemplatePath, "utf8");
  const coverRenderer = await readFile(join(import.meta.dir, "render-covers.ts"), "utf8");
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
    knownPaths.add(authorPath(front.lang, front.author));
    knownPaths.add(editorialPolicyPath(front.lang));
  }

  const keywords = new Map<string, string>();
  const slugs = new Map<string, string>();
  const posts: BlogPost[] = [];

  for (const { file, front, tree, body } of parsed) {
    const lang = front.lang;
    const problems: string[] = [];

    if (front.slug === editorialPolicySlugs[lang]) problems.push(`slug "${front.slug}" is reserved for the editorial policy`);
    const slugKey = `${lang}:${front.slug}`;
    if (slugs.has(slugKey)) problems.push(`slug already used by ${slugs.get(slugKey)}`);
    slugs.set(slugKey, file);
    const keywordKey = `${lang}:${front.keyword.toLowerCase().trim()}`;
    if (keywords.has(keywordKey)) problems.push(`keyword "${front.keyword}" already targeted by ${keywords.get(keywordKey)}`);
    keywords.set(keywordKey, file);

    const headings: Array<{ depth: number; text: string }> = [];
    const imageNodes: MdNode[] = [];
    let tldrCount = 0;
    walk(tree, (node) => {
      if (node.type === "blockquote" && isTldr(node)) {
        tldrCount++;
        if (headings.some((heading) => heading.depth === 2)) problems.push(`the ${tldrMarker} summary must come before the first section`);
      }
      if (node.type === "image") imageNodes.push(node);
      if (node.type === "paragraph" && node.children?.some((child) => child.type === "image")
        && (node.children.length !== 1)) problems.push("an image must stand alone in its own paragraph");
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

    if (tldrCount > 1) problems.push(`only one ${tldrMarker} summary is allowed`);
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

    const images = new Map<string, ArticleImage>();
    for (const node of imageNodes) {
      const image = await planImage(contentDir, lang, front.slug, node, problems);
      if (image) images.set(image.url, image);
    }

    if (problems.length) {
      errors.push(...problems.map((problem) => `${file}: ${problem}`));
      continue;
    }

    const hast = await unified()
      .use(remarkRehype)
      .use(rehypeSlug)
      .run(tree as never) as unknown as HastNode;
    addCopyButtons(hast, lang);
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
        if ([faqHeadings[lang], sourcesHeadings[lang]].includes(text(node).trim())) node.properties.className = ["blog-appendix"];
      }
      if (node.type === "element" && node.tagName === "blockquote" && isTldr(node as never)) {
        const first = node.children!.find((child) => child.tagName === "p")!;
        const marker = first.children![0]!;
        marker.value = marker.value!.replace(tldrMarker, "").replace(/^\s+/, "");
        if (!marker.value && first.children!.length === 1) node.children = node.children!.filter((child) => child !== first);
        node.tagName = "aside";
        node.properties = { className: ["blog-tldr"], ariaLabel: tldrTitles[lang] };
        node.children = [{ type: "element", tagName: "p", properties: { className: ["blog-tldr-title"] }, children: [{ type: "text", value: tldrTitles[lang] }] }, ...node.children!];
      }
      // A paragraph holding only an image becomes a figure with responsive WebP sources.
      const only = node.children?.length === 1 ? node.children[0] : undefined;
      if (node.type === "element" && node.tagName === "p" && only?.tagName === "img") {
        const image = images.get(String(only.properties?.src));
        if (!image) return;
        const first = image.renditions[0]!;
        const img: HastNode = {
          type: "element", tagName: "img", children: [], properties: {
            src: first.path,
            srcSet: image.renditions.map((rendition) => `${rendition.path} ${rendition.width}w`).join(", "),
            sizes: imageSizes,
            width: first.width,
            height: Math.round(image.height * first.width / image.width),
            alt: image.alt,
            loading: "lazy",
            decoding: "async",
          },
        };
        node.tagName = "figure";
        node.properties = {};
        node.children = [img, {
          type: "element", tagName: "figcaption", properties: {}, children: [
            ...(image.title ? [{ type: "text", value: image.title } as HastNode] : []),
            {
              type: "element", tagName: "a", properties: {
                className: ["blog-image-full"], href: image.renditions.at(-1)!.path,
                target: "_blank", rel: ["noopener"],
                ariaLabel: lang === "de" ? `Bild in voller Größe öffnen (neuer Tab): ${image.alt}` : `Open full-size image (new tab): ${image.alt}`,
              }, children: [{ type: "text", value: lang === "de" ? "Bild in voller Größe ansehen" : "View full-size image" }],
            },
          ],
        }];
      }
    });
    const html = unified().use(rehypeStringify).stringify(hast as never);
    const words = body.split(/\s+/).filter(Boolean).length;

    const coverHash = createHash("sha256").update(JSON.stringify([coverTemplate, coverRenderer, lang, heading])).digest("hex").slice(0, 10);
    const coverBase = `/blog/covers/${front.slug}-${coverHash}`;
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
      published: front.published,
      updated: front.updated,
      imageAlt: front.imageAlt,
      readingMinutes: Math.max(1, Math.round(words / 220)),
      toc,
      html,
      keyword: front.keyword,
      images: [...images.values()].flatMap((image) => image.renditions),
      cover: {
        hash: coverHash, lang, title: heading,
        path: `${coverBase}-social.png`,
        cardPath: `${coverBase}-card.webp`,
      },
    });
  }

  posts.sort((a, b) => b.published.localeCompare(a.published) || a.slug.localeCompare(b.slug));
  return { posts, errors };
}
