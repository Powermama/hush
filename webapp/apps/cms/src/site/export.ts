// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// What the website builds from: every published post as a hush-seo Markdown
// file (<lang>/<slug>.md) and the originals of the images it references
// (<lang>/media/<slug>/<name>). The website runs its existing generator over
// that directory, so pages, feeds, covers and image renditions come out as if
// the files were in the repository, and serves the revision back so the CMS
// knows when a change is live.
import { formatArticle } from "@hush/article";
import type { Database } from "../db/client";
import { siteState } from "../db/schema";
import { listMedia } from "../media/service";
import { editableFields, listPosts, type Post } from "../posts/service";

export type ExportFile = { path: string; markdown: string; media: Array<{ path: string; sha256: string; contentType: string }> };
export type SiteExport = { revision: number; files: ExportFile[] };

const isoDay = (date: Date) => date.toISOString().slice(0, 10);

/** The post as the Markdown file the hush-seo skill would have written. */
export function postFile(post: Post) {
  const { markdown, ...fields } = editableFields(post);
  const published = isoDay(post.publishedAt!);
  // An edit before the publication date (a scheduled post) is not an update.
  const updated = [published, isoDay(post.updatedAt)].sort().at(-1)!;
  return formatArticle({
    front: { ...fields, published, updated, schema: ["BlogPosting"], draft: false },
    body: markdown,
  });
}

/**
 * Published posts in a stable order, with the site revision they reflect. One
 * repeatable-read snapshot, so the revision and the posts always agree.
 */
export function exportSite(db: Database): Promise<SiteExport> {
  return db.transaction(async (tx) => {
    const [state] = await tx.select({ revision: siteState.revision }).from(siteState);
    const posts = (await listPosts(tx, { status: "published" }))
      .sort((a, b) => `${a.lang}/${a.slug}`.localeCompare(`${b.lang}/${b.slug}`));
    const files: ExportFile[] = [];
    for (const post of posts) {
      const media = await listMedia(tx, post.id);
      files.push({
        path: `${post.lang}/${post.slug}.md`,
        markdown: postFile(post),
        media: media.map((row) => ({ path: `${post.lang}/media/${post.slug}/${row.name}`, sha256: row.sha256, contentType: row.contentType })),
      });
    }
    return { revision: state!.revision, files };
  }, { isolationLevel: "repeatable read", accessMode: "read only" });
}
