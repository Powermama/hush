// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The article file format written by the hush-seo skill: YAML front matter,
// then the Markdown body. Free of Node-only dependencies, so the hush-cms CLI
// compiles it into a standalone binary.
import { parse as parseYaml } from "yaml";
import { z } from "zod";
import { blogAuthorIds } from "./authors.ts";
import { blogArticleTypes, blogClusterIds, blogLanguages } from "./taxonomy.ts";

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

export function splitFrontMatter(source: string) {
  const match = /^---\n([\s\S]*?)\n---\n?([\s\S]*)$/.exec(source.replace(/\r\n/g, "\n"));
  if (!match) throw new Error("missing front matter block delimited by ---");
  return { data: parseYaml(match[1]!) as unknown, body: match[2]! };
}

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
 * Writes an article in the hush-seo file format: front matter in the schema's
 * field order, one JSON value per line (valid YAML), then the body.
 * parseArticle(formatArticle(article)) returns the same article.
 */
export function formatArticle({ front, body }: ParsedArticle): string {
  const fields = Object.keys(frontMatterFields.shape) as Array<keyof FrontMatter>;
  const lines = fields.map((field) => `${field}: ${JSON.stringify(front[field])}`);
  return `---\n${lines.join("\n")}\n---\n${body}`;
}

/** Front matter keys that record when and whether an article is live. The CMS sets them through schedule and publish, never from a file. */
export const lifecycleKeys = ["published", "updated", "draft", "schema"] as const;

/** What a post holds of an article: its front matter without the lifecycle keys, and its body. */
export type ArticleContent = Omit<FrontMatter, (typeof lifecycleKeys)[number]> & { markdown: string };

export function articleContent({ front, body }: ParsedArticle): ArticleContent {
  const { published: _published, updated: _updated, draft: _draft, schema: _schema, ...content } = front;
  return { ...content, markdown: body };
}

/**
 * Reads an article file as draft content. Unlike parseArticle it checks only
 * the field names: a draft may be incomplete or outside the contract's limits,
 * and the CMS checks the values and applies the contract when the post goes
 * live. Lifecycle keys are dropped.
 */
export function readDraftContent(source: string): { content?: Record<string, unknown> & { markdown: string }; problems: string[] } {
  let split;
  try {
    split = splitFrontMatter(source);
  } catch (error) {
    return { problems: [(error as Error).message] };
  }
  const data = split.data ?? {};
  if (typeof data !== "object" || Array.isArray(data)) return { problems: ["front matter must be a list of fields"] };
  const unknown = Object.keys(data).filter((key) => !(key in frontMatterFields.shape));
  if (unknown.length) return { problems: unknown.map((key) => `front matter ${key}: unknown field`) };
  const content: Record<string, unknown> = { ...data };
  for (const key of lifecycleKeys) delete content[key];
  return { content: { ...content, markdown: split.body }, problems: [] };
}
