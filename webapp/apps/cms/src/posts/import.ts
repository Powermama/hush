// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Imports articles written as Markdown files (the hush-seo format: <lang>/<slug>.md
// with images in <lang>/media/<slug>/). Safe to run again: posts are matched by
// language and slug and updated only where they differ, and published articles
// keep their original dates.
import { parseArticle } from "@hush/article";
import { blogLanguages } from "@hush/article/taxonomy";
import { and, eq } from "drizzle-orm";
import { readdir } from "node:fs/promises";
import { extname, join } from "node:path";
import { posts } from "../db/schema";
import { uploadMedia, type Cms } from "../media/service";
import { PostError } from "./errors";
import { postFields } from "./fields";
import { createDraft, editableFields, getPost, publishPost, updatePost } from "./service";

const contentTypes: Record<string, string> = { ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp" };
const day = (date: string) => new Date(`${date}T00:00:00.000Z`);

export type ImportReport = { imported: string[]; published: string[]; failed: Array<{ file: string; problems: string[] }> };

export async function importArticles(cms: Cms, contentDir: string, actor = "import"): Promise<ImportReport> {
  const report: ImportReport = { imported: [], published: [], failed: [] };
  const toPublish: Array<{ file: string; id: string; publishedAt: Date; updatedAt: Date }> = [];

  for (const lang of blogLanguages) {
    const files = (await readdir(join(contentDir, lang)).catch(() => [] as string[])).filter((file) => file.endsWith(".md")).sort();
    for (const file of files) {
      const where = `${lang}/${file}`;
      const { article, problems } = parseArticle(await Bun.file(join(contentDir, lang, file)).text());
      if (!article) { report.failed.push({ file: where, problems }); continue; }
      const { published, updated, draft, schema: _schema, ...metadata } = article.front;
      const fields = { ...metadata, markdown: article.body };
      try {
        const [existing] = await cms.db.select({ id: posts.id }).from(posts).where(and(eq(posts.lang, fields.lang), eq(posts.slug, fields.slug)));
        const id = existing?.id ?? (await createDraft(cms.db, fields, actor)).id;
        const mediaDir = join(contentDir, lang, "media", fields.slug);
        for (const name of (await readdir(mediaDir).catch(() => [] as string[])).sort()) {
          const type = contentTypes[extname(name)];
          if (type) await uploadMedia(cms, id, name, new Uint8Array(await Bun.file(join(mediaDir, name)).arrayBuffer()), type);
        }
        // Only a real difference is an edit: an unchanged article keeps its
        // date, revision history and site revision.
        if (existing && JSON.stringify(editableFields(await getPost(cms.db, id))) !== JSON.stringify(postFields.parse(fields))) {
          await updatePost(cms, id, fields, actor);
        }
        report.imported.push(where);
        if (!draft) toPublish.push({ file: where, id, publishedAt: day(published), updatedAt: day(updated) });
      } catch (error) {
        report.failed.push({ file: where, problems: error instanceof PostError ? [error.message, ...error.problems] : [String(error)] });
      }
    }
  }

  // Articles may link to each other; publish in passes until no more can go live.
  let pending = toPublish;
  while (pending.length) {
    const blocked: typeof pending = [];
    const errors = new Map<string, string[]>();
    for (const item of pending) {
      try {
        await publishPost(cms, item.id, actor, { publishedAt: item.publishedAt, updatedAt: item.updatedAt });
        report.published.push(item.file);
      } catch (error) {
        if (!(error instanceof PostError)) throw error;
        blocked.push(item);
        errors.set(item.file, [error.message, ...error.problems]);
      }
    }
    if (blocked.length === pending.length) {
      for (const item of blocked) report.failed.push({ file: item.file, problems: errors.get(item.file)! });
      break;
    }
    pending = blocked;
  }
  return report;
}
