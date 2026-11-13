// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The hush article contract: parses one Markdown article, validates it and
// renders it to HTML. Pure: images and the surrounding site arrive through the
// context, so the static blog build and the CMS share one implementation.
import { createHash } from "node:crypto";
import sharp from "sharp";
import rehypeSlug from "rehype-slug";
import rehypeStringify from "rehype-stringify";
import remarkGfm from "remark-gfm";
import remarkParse from "remark-parse";
import remarkRehype from "remark-rehype";
import { unified } from "unified";
import { parse as parseYaml } from "yaml";
import { z } from "zod";
import { blogAuthorIds, type BlogAuthorId } from "./authors.ts";
import {
  blogArticleTypes, blogClusterIds, blogLanguages, blogPath, editorialPolicySlugs, type BlogClusterId, type BlogLanguage,
} from "./taxonomy.ts";

/** The front matter fields written by the hush-seo skill. Unknown fields fail loudly. */
export const frontMatterFields = z.object({
  title: z.string().min(50).max(60),
  description: z.string().min(140).max(160),
  slug: z.string().regex(/^[a-z0-9]+(-[a-z0-9]+)*$/),
  lang: z.enum(blogLanguages),
  keyword: z.string().min(2),
  secondaryKeywords: z.array(z.string().min(2)).max(8),
  type: z.enum(blogArticleTypes),
  cluster: z.enum(blogClusterIds),
  author: z.enum(blogAuthorIds),
  published: z.iso.date(),
  updated: z.iso.date(),
  imageAlt: z.string().min(10).max(160),
  schema: z.tuple([z.literal("BlogPosting")]),
  draft: z.boolean(),
}).strict();

/** Front matter as a whole: its fields plus the rules that relate them. */
export const frontMatterSchema = frontMatterFields.refine((data) => data.updated >= data.published, {
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

type MdNode = { type: string; depth?: number; url?: string; alt?: string; title?: string | null; value?: string; children?: MdNode[] };
type HastNode = { type: string; tagName?: string; properties?: Record<string, unknown>; value?: string; children?: HastNode[] };

type ArticleImage = { url: string; alt: string; title?: string; width: number; height: number; renditions: BlogImageOutput[] };

/** Validates an article image and plans its WebP renditions. */
async function planImage(context: ArticleContext, slug: string, node: MdNode, problems: string[]): Promise<ArticleImage | undefined> {
  const url = node.url ?? "";
  const match = imagePath.exec(url);
  if (!match) { problems.push(`image "${url}" must be media/${slug}/<name>.png|jpg|webp`); return; }
  if (match[1] !== slug) { problems.push(`image "${url}" must live in media/${slug}/`); return; }
  const alt = (node.alt ?? "").trim();
  if (alt.length < 10 || alt.length > 160) problems.push(`image "${url}" needs alt text of 10 to 160 characters`);
  const file = await context.loadImage(url);
  if (!file) { problems.push(`image "${url}" does not exist`); return; }
  const { width, height } = await sharp(file.bytes).metadata();
  if (!width || !height) { problems.push(`image "${url}" cannot be read`); return; }
  if (width < imageWidths[0]!) problems.push(`image "${url}" is ${width}px wide; provide at least ${imageWidths[0]}px`);
  // Content-hashed names: a changed image gets new URLs, so caches never serve a stale one.
  const hash = createHash("sha256").update(file.bytes).digest("hex").slice(0, 10);
  const renditions = [...new Set(imageWidths.map((target) => Math.min(target, width)))].map((target) => ({
    source: file.source, width: target, path: `/blog/media/${slug}-${match[2]}-${hash}-${target}.webp`,
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

/** What an article needs from the site around it. */
export type ArticleContext = {
  /** Site paths the article may link to: pages, published articles, indexes, authors. */
  knownPaths: ReadonlySet<string>;
  /** Reads an image referenced as media/<slug>/<file>; `source` is passed through to the rendition. */
  loadImage(url: string): Promise<{ bytes: Uint8Array; source: string } | undefined>;
  /** The cover template and renderer sources: changing either renames every cover. */
  coverSeed: readonly string[];
};

export type ParsedArticle = { front: FrontMatter; body: string };

/** Splits and validates the front matter. Problems carry no file prefix. */
export function parseArticle(source: string): { article?: ParsedArticle; problems: string[] } {
  let split;
  try {
    split = splitFrontMatter(source);
  } catch (error) {
    return { problems: [(error as Error).message] };
  }
  const result = frontMatterSchema.safeParse(split.data);
  if (!result.success) {
    return { problems: result.error.issues.map((issue) => `front matter ${issue.path.join(".") || "(root)"}: ${issue.message}`) };
  }
  return { article: { front: result.data, body: split.body }, problems: [] };
}

/**
 * Checks one article against the contract and renders it. Rules that need the
 * other articles (duplicate slugs and keywords) belong to the caller.
 */
export async function renderArticle({ front, body }: ParsedArticle, context: ArticleContext): Promise<{ post?: BlogPost; problems: string[] }> {
  const lang = front.lang;
  const problems: string[] = [];
  const tree = unified().use(remarkParse).use(remarkGfm).parse(body) as unknown as MdNode;
  const knownPaths = context.knownPaths;

  if (front.slug === editorialPolicySlugs[lang]) problems.push(`slug "${front.slug}" is reserved for the editorial policy`);
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
    const image = await planImage(context, front.slug, node, problems);
    if (image) images.set(image.url, image);
  }

  if (problems.length) return { problems };

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

  const coverHash = createHash("sha256").update(JSON.stringify([...context.coverSeed, lang, heading])).digest("hex").slice(0, 10);
  const coverBase = `/blog/covers/${front.slug}-${coverHash}`;
  const post: BlogPost = {
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
  };
  return { post, problems };
}
