// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Imports articles written as Markdown files (the hush-seo format: <lang>/<slug>.md
// with images in <lang>/media/<slug>/). Safe to run again: posts are matched by
// language and slug and updated only where they differ, and published articles
// keep their original dates.
import { articleContent, parseArticle } from "@hush/article/file";
import { blogLanguages } from "@hush/article/taxonomy";
import { and, eq } from "drizzle-orm";
import { readdir } from "node:fs/promises";
import { extname, join } from "node:path";
import { posts } from "../db/schema";
import { uploadMedia, type Cms } from "../media/service";
import { checkPost } from "./contract";
import { PostError } from "./errors";
import { postFields } from "./fields";
import { createDraft, editableFields, getPost, publishPost, updatePost } from "./service";

const contentTypes: Record<string, string> = { ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp" };
const day = (date: string) => new Date(`${date}T00:00:00.000Z`);

type Candidate = {
  file: string; id: string; lang: string; slug: string; author: string; keyword: string; publishedAt: Date; updatedAt: Date;
};

export type ImportReport = { imported: string[]; published: string[]; failed: Array<{ file: string; problems: string[] }> };

export async function importArticles(cms: Cms, contentDir: string, actor = "import"): Promise<ImportReport> {
  const report: ImportReport = { imported: [], published: [], failed: [] };
  const toPublish: Candidate[] = [];

  for (const lang of blogLanguages) {
    const files = (await readdir(join(contentDir, lang)).catch(() => [] as string[])).filter((file) => file.endsWith(".md")).sort();
    for (const file of files) {
      const where = `${lang}/${file}`;
      const { article, problems } = parseArticle(await Bun.file(join(contentDir, lang, file)).text());
      if (!article) { report.failed.push({ file: where, problems }); continue; }
      const { published, updated, draft } = article.front;
      const fields = articleContent(article);
      try {
        const [existing] = await cms.db.select({ id: posts.id }).from(posts).where(and(eq(posts.lang, fields.lang), eq(posts.slug, fields.slug)));
        const id = existing?.id ?? (await createDraft(cms.db, fields, actor)).id;
        const mediaDir = join(contentDir, lang, "media", fields.slug);
        for (const name of (await readdir(mediaDir).catch(() => [] as string[])).sort()) {
          const type = contentTypes[extname(name)];
          if (type) await uploadMedia(cms, id, name, new Uint8Array(await Bun.file(join(mediaDir, name)).arrayBuffer()), type, actor);
        }
        // Only a real difference is an edit: an unchanged article keeps its
        // date, revision history and site revision.
        if (existing && JSON.stringify(editableFields(await getPost(cms.db, id))) !== JSON.stringify(postFields.parse(fields))) {
          await updatePost(cms, id, fields, actor);
        }
        report.imported.push(where);
        if (!draft) toPublish.push({ file: where, id, lang: fields.lang, slug: fields.slug, author: fields.author, keyword: fields.keyword, publishedAt: day(published), updatedAt: day(updated) });
      } catch (error) {
        report.failed.push({ file: where, problems: error instanceof PostError ? [error.message, ...error.problems] : [String(error)] });
      }
    }
  }

  const { published, failed } = await publishTogether(cms, toPublish, actor);
  report.published.push(...published);
  report.failed.push(...failed);
  return report;
}

/**
 * Publishes the articles that can go live together. Articles may link to each
 * other, also in a cycle, so each is checked as if all candidates were live;
 * an article that fails leaves the set and the rest are checked again, until
 * the set is stable. Only then is anything published, so no published article
 * links to one that stays a draft.
 */
async function publishTogether(cms: Cms, candidates: Candidate[], actor: string) {
  const failed: ImportReport["failed"] = [];
  let set = candidates;
  for (;;) {
    const rejected = new Map<Candidate, string[]>();
    const keywords = new Map<string, Candidate>();
    for (const item of set) {
      // Within the set, as among live posts, a keyword belongs to one article per language.
      const keyword = `${item.lang}:${item.keyword.toLowerCase().trim()}`;
      const owner = keywords.get(keyword);
      if (owner) { rejected.set(item, [`keyword "${item.keyword}" already targeted by ${owner.slug}`]); continue; }
      keywords.set(keyword, item);
      const post = await getPost(cms.db, item.id);
      const { post: rendered, problems } = await checkPost(cms, item.id, editableFields(post), item.publishedAt, item.updatedAt, set);
      if (!rendered || problems.length) rejected.set(item, problems);
    }
    if (!rejected.size) break;
    for (const [item, problems] of rejected) failed.push({ file: item.file, problems: ["The post does not meet the article contract.", ...problems] });
    set = set.filter((item) => !rejected.has(item));
  }
  const published: string[] = [];
  for (const item of set) {
    await publishPost(cms, item.id, actor, { publishedAt: item.publishedAt, updatedAt: item.updatedAt }, set);
    published.push(item.file);
  }
  return { published, failed };
}
