// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Runs the @hush/article contract against a stored post, with the site as the
// database knows it: published articles, their authors, the blog indexes and
// the site pages articles may link to.
import { frontMatterSchema, renderArticle, type BlogPost } from "@hush/article";
import { authorPath } from "@hush/article/authors";
import { blogPath, editorialPolicyPath, linkableSitePaths, type BlogLanguage } from "@hush/article/taxonomy";
import { and, eq, ne, sql } from "drizzle-orm";
import type { Database } from "../db/client";
import { posts } from "../db/schema";
import type { PostFields } from "./fields";

const isoDate = (date: Date) => date.toISOString().slice(0, 10);

export async function checkPost(db: Database, id: string, fields: PostFields, publishedAt: Date, updatedAt: Date)
  : Promise<{ post?: BlogPost; problems: string[] }> {
  const { markdown, ...metadata } = fields;
  const front = frontMatterSchema.safeParse({
    ...metadata, schema: ["BlogPosting"], draft: false,
    published: isoDate(publishedAt), updated: isoDate(updatedAt < publishedAt ? publishedAt : updatedAt),
  });
  if (!front.success) {
    return { problems: front.error.issues.map((issue) => `front matter ${issue.path.join(".") || "(root)"}: ${issue.message}`) };
  }
  const lang = fields.lang as BlogLanguage;
  const live = await db.select({ slug: posts.slug, author: posts.author, keyword: posts.keyword }).from(posts)
    .where(and(eq(posts.lang, lang), eq(posts.status, "published"), ne(posts.id, id)));

  const problems: string[] = [];
  const [duplicate] = await db.select({ slug: posts.slug }).from(posts).where(and(
    eq(posts.lang, lang), ne(posts.status, "draft"), ne(posts.id, id),
    sql`lower(trim(${posts.keyword})) = ${fields.keyword.toLowerCase().trim()}`,
  ));
  if (duplicate) problems.push(`keyword "${fields.keyword}" already targeted by ${duplicate.slug}`);

  const knownPaths = new Set<string>([...linkableSitePaths, blogPath(lang), editorialPolicyPath(lang)]);
  for (const post of [...live, { slug: fields.slug, author: fields.author }]) {
    knownPaths.add(blogPath(lang, post.slug));
    knownPaths.add(authorPath(lang, post.author as Parameters<typeof authorPath>[1]));
  }
  const rendered = await renderArticle({ front: front.data, body: markdown }, {
    knownPaths,
    // Media storage arrives with the import; until then articles cannot embed images.
    loadImage: async () => undefined,
    coverSeed: [],
  });
  return { post: rendered.post, problems: [...problems, ...rendered.problems] };
}
