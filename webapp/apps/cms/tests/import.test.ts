// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// CMS-IMPORT journeys: Markdown articles in the hush-seo format become posts.
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { LocalObjectStore } from "../src/storage/object-store";
import { importArticles } from "../src/posts/import";
import { listPosts, listRevisions } from "../src/posts/service";
import { createTestDatabase, serverUrl } from "./database";
import { validPost } from "./fixtures";
import { png } from "./media.test";

function article(fields: ReturnType<typeof validPost>, front: { published: string; updated: string; draft: boolean }) {
  const { markdown, secondaryKeywords, ...rest } = fields;
  const yaml = Object.entries({ ...rest, ...front }).map(([key, value]) => `${key}: ${JSON.stringify(value)}`);
  return `---\n${yaml.join("\n")}\nsecondaryKeywords: ${JSON.stringify(secondaryKeywords)}\nschema: ["BlogPosting"]\n---\n\n${markdown}\n`;
}

describe.skipIf(!serverUrl)("CMS import", () => {
  let database: Awaited<ReturnType<typeof createTestDatabase>>;
  let cms: { db: Awaited<ReturnType<typeof createTestDatabase>>["db"]; media: LocalObjectStore };
  let content = "";

  beforeAll(async () => {
    database = await createTestDatabase();
    cms = { db: database.db, media: new LocalObjectStore(await mkdtemp(join(tmpdir(), "hush-cms-media-"))) };
    content = await mkdtemp(join(tmpdir(), "hush-cms-content-"));
    await mkdir(join(content, "en", "media", "linked-guide"), { recursive: true });
    // "linked-guide" links to "base-guide", so it can only go live after it.
    const linked = validPost({
      slug: "linked-guide", keyword: "linked guide",
      markdown: validPost().markdown.replace("[the home page](/)", "[the base guide](/blog/base-guide)")
        .replace("## How does it work?", '![A test image for the import](media/linked-guide/shot.png)\n\n## How does it work?'),
    });
    await writeFile(join(content, "en", "linked-guide.md"), article(linked, { published: "2026-11-12", updated: "2026-11-13", draft: false }));
    await writeFile(join(content, "en", "media", "linked-guide", "shot.png"), await png(900));
    await writeFile(join(content, "en", "base-guide.md"), article(validPost({ slug: "base-guide", keyword: "base guide" }), { published: "2026-11-10", updated: "2026-11-10", draft: false }));
    await writeFile(join(content, "en", "unfinished.md"), article(validPost({ slug: "unfinished", keyword: "unfinished" }), { published: "2026-11-13", updated: "2026-11-13", draft: true }));
  });
  afterAll(async () => { await database?.drop(); });

  test("CMS-IMPORT-001 imports articles with images, publishing them in link order with their dates", async () => {
    const report = await importArticles(cms, content);
    expect(report.failed).toEqual([]);
    expect(report.imported.sort()).toEqual(["en/base-guide.md", "en/linked-guide.md", "en/unfinished.md"]);
    expect(report.published).toEqual(["en/base-guide.md", "en/linked-guide.md"]);
    const posts = Object.fromEntries((await listPosts(cms.db, {})).map((post) => [post.slug, post]));
    expect(posts["unfinished"]!.status).toBe("draft");
    expect(posts["linked-guide"]).toMatchObject({ status: "published", secondaryKeywords: ["offline dictation mac", "local speech to text"] });
    expect(posts["linked-guide"]!.publishedAt!.toISOString()).toBe("2026-11-12T00:00:00.000Z");
    expect(posts["linked-guide"]!.rendition!.html).toContain("-680.webp");
  });

  test("CMS-IMPORT-002 running it again changes nothing", async () => {
    const before = await listPosts(cms.db, {});
    const revisionsBefore = (await listRevisions(cms.db, before.find((post) => post.slug === "linked-guide")!.id)).length;
    const report = await importArticles(cms, content);
    expect(report.failed).toEqual([]);
    const after = await listPosts(cms.db, {});
    expect(after.length).toBe(before.length);
    const linked = after.find((post) => post.slug === "linked-guide")!;
    expect(linked.status).toBe("published");
    expect(linked.publishedAt!.toISOString()).toBe("2026-11-12T00:00:00.000Z");
    expect(linked.updatedAt.getTime()).toBe(before.find((post) => post.slug === "linked-guide")!.updatedAt.getTime());
    expect((await listRevisions(cms.db, linked.id)).length).toBe(revisionsBefore);
  });
});
