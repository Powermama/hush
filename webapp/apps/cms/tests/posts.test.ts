// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// CMS journeys (docs/user-journeys/cms.md), through the HTTP API as an agent or
// script uses it, against a real PostgreSQL database.
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { sql } from "drizzle-orm";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createApp } from "../src/app";
import { createToken } from "../src/auth/tokens";
import type { Database } from "../src/db/client";
import { LocalObjectStore } from "../src/storage/object-store";
import { publishDuePosts } from "../src/posts/service";
import { createTestDatabase, serverUrl } from "./database";
import { validPost } from "./fixtures";

describe.skipIf(!serverUrl)("CMS API", () => {
  let database: Awaited<ReturnType<typeof createTestDatabase>>;
  let db: Database;
  let app: ReturnType<typeof createApp>;
  const tokens = { reader: "", writer: "", publisher: "" };

  beforeAll(async () => {
    database = await createTestDatabase();
    db = database.db;
    app = createApp({ db, media: new LocalObjectStore(await mkdtemp(join(tmpdir(), "hush-cms-media-"))) });
    tokens.reader = await createToken(db, { name: "reader", scopes: ["posts:read"] });
    tokens.writer = await createToken(db, { name: "agent", scopes: ["posts:read", "posts:write"] });
    tokens.publisher = await createToken(db, { name: "owner", scopes: ["posts:read", "posts:write", "posts:publish"] });
  });
  afterAll(async () => { await database?.drop(); });

  const call = (method: string, path: string, token: string, body?: unknown) => app.request(path, {
    method,
    headers: { authorization: `Bearer ${token}`, ...(body ? { "content-type": "application/json" } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const read = (response: Response) => response.json() as Promise<Record<string, any>>;
  const draft = async (overrides = {}) => {
    const response = await call("POST", "/v1/posts", tokens.writer, validPost(overrides));
    expect(response.status).toBe(201);
    return read(response);
  };

  test("CMS-API-001 requires a token with the right scope", async () => {
    expect((await app.request("/v1/posts")).status).toBe(401);
    expect((await call("GET", "/v1/posts", "hcms_unknown")).status).toBe(401);
    expect((await call("POST", "/v1/posts", tokens.reader, validPost({ slug: "reader-try" }))).status).toBe(403);
    const post = await draft({ slug: "scope-check", keyword: "scope check" });
    const refused = await call("POST", `/v1/posts/${post.id}/publish`, tokens.writer);
    expect(refused.status).toBe(403);
    expect((await read(refused)).error.message).toContain("posts:publish");
    expect((await app.request("/v1/posts")).headers.get("x-robots-tag")).toBe("noindex, nofollow");
  });

  test("CMS-API-012 tells a token its name, scopes and expiry", async () => {
    expect((await app.request("/v1/me")).status).toBe(401);
    expect(await read(await call("GET", "/v1/me", tokens.writer))).toEqual({ actor: "token:agent", scopes: ["posts:read", "posts:write"], expiresAt: null });
    const expiresAt = new Date("2030-01-01T00:00:00.000Z");
    const expiring = await createToken(db, { name: "expiring", scopes: ["posts:read"], expiresAt });
    expect((await read(await call("GET", "/v1/me", expiring))).expiresAt).toBe(expiresAt.toISOString());
  });

  test("CMS-API-002 keeps a draft with its fields and keyword order", async () => {
    const post = await draft({ slug: "draft-only", keyword: "draft only", secondaryKeywords: ["b phrase", "a phrase"] });
    expect(post.status).toBe("draft");
    expect(post.secondaryKeywords).toEqual(["b phrase", "a phrase"]);
    expect(post.rendition).toBeNull();
    const drafts = await read(await call("GET", "/v1/posts?status=draft&lang=en", tokens.reader));
    expect(drafts.posts.map((item: { id: string }) => item.id)).toContain(post.id);
    const taken = await call("POST", "/v1/posts", tokens.writer, validPost({ slug: "draft-only", keyword: "another" }));
    expect(taken.status).toBe(409);
  });

  test("CMS-API-003 refuses to publish a post that breaks the article contract", async () => {
    const post = await draft({ slug: "no-faq", keyword: "no faq", markdown: "# A heading\n\nText without the questions section." });
    const response = await call("POST", `/v1/posts/${post.id}/publish`, tokens.publisher);
    expect(response.status).toBe(422);
    const { error } = await read(response);
    expect(error.code).toBe("contract_failed");
    expect(error.problems.join("\n")).toContain('missing the "## Frequently asked questions" section');
    expect((await read(await call("GET", `/v1/posts/${post.id}`, tokens.reader))).status).toBe("draft");
  });

  test("CMS-API-004 publishes a valid post with its rendered HTML and a revision", async () => {
    const post = await draft({ slug: "goes-live", keyword: "goes live" });
    const published = await read(await call("POST", `/v1/posts/${post.id}/publish`, tokens.publisher));
    expect(published.status).toBe("published");
    expect(Date.parse(published.publishedAt)).toBeLessThanOrEqual(Date.now());
    expect(published.rendition.html).toContain('<h2 id="how-does-it-work">');
    expect(published.rendition.html).not.toContain("<h1");
    const { revisions } = await read(await call("GET", `/v1/posts/${post.id}/revisions`, tokens.reader));
    expect(revisions.map((revision: { status: string }) => revision.status)).toEqual(["published", "draft"]);
    expect(revisions[0].actor).toBe("token:owner");
    const twin = await draft({ slug: "same-keyword", keyword: "Goes Live " });
    const clash = await read(await call("POST", `/v1/posts/${twin.id}/publish`, tokens.publisher));
    expect(clash.error.problems).toContain('keyword "Goes Live " already targeted by goes-live');
  });

  test("CMS-API-005 publishes a scheduled post once it is due, exactly once", async () => {
    const post = await draft({ slug: "scheduled", keyword: "scheduled post" });
    expect((await call("POST", `/v1/posts/${post.id}/schedule`, tokens.publisher, { publishedAt: new Date(Date.now() - 1000).toISOString() })).status).toBe(422);
    const at = new Date(Date.now() + 3_600_000).toISOString();
    const scheduled = await read(await call("POST", `/v1/posts/${post.id}/schedule`, tokens.publisher, { publishedAt: at }));
    expect(scheduled.status).toBe("scheduled");
    expect(scheduled.rendition.html).toContain("<h2");
    expect((await publishDuePosts(db)).map((due) => due.id)).not.toContain(post.id);
    await db.execute(sql`update posts set published_at = now() - interval '1 second' where id = ${post.id}`);
    expect((await publishDuePosts(db)).map((due) => due.id)).toEqual([post.id]);
    expect(await publishDuePosts(db)).toEqual([]);
    const live = await read(await call("GET", `/v1/posts/${post.id}`, tokens.reader));
    expect(live.status).toBe("published");
    const { revisions } = await read(await call("GET", `/v1/posts/${post.id}/revisions`, tokens.reader));
    expect(revisions[0]).toMatchObject({ status: "published", actor: "scheduler" });
  });

  test("CMS-API-006 unpublishes back to a draft and keeps the original date", async () => {
    const post = await draft({ slug: "comes-down", keyword: "comes down" });
    const published = await read(await call("POST", `/v1/posts/${post.id}/publish`, tokens.publisher));
    const draftAgain = await read(await call("POST", `/v1/posts/${post.id}/unpublish`, tokens.publisher));
    expect(draftAgain).toMatchObject({ status: "draft", rendition: null, publishedAt: published.publishedAt });
    const republished = await read(await call("POST", `/v1/posts/${post.id}/publish`, tokens.publisher));
    expect(republished.publishedAt).toBe(published.publishedAt);
  });

  test("CMS-API-007 keeps a live post valid when it is edited", async () => {
    const post = await draft({ slug: "live-edit", keyword: "live edit" });
    await call("POST", `/v1/posts/${post.id}/publish`, tokens.publisher);
    const broken = await call("PATCH", `/v1/posts/${post.id}`, tokens.writer, { markdown: "# Only a heading" });
    expect(broken.status).toBe(422);
    const edited = await read(await call("PATCH", `/v1/posts/${post.id}`, tokens.writer, {
      markdown: `${validPost().markdown}\n\n### Is it free?\n\nYes.`,
    }));
    expect(edited.rendition.html).toContain("Is it free?");
  });

  test("CMS-API-008 restores an earlier revision", async () => {
    const post = await draft({ slug: "restore-me", keyword: "restore me", title: "The first title of this article, long enough to pass" });
    await call("PATCH", `/v1/posts/${post.id}`, tokens.writer, { title: "The second title of this article, long enough to pass" });
    const { revisions } = await read(await call("GET", `/v1/posts/${post.id}/revisions`, tokens.reader));
    const first = revisions.at(-1);
    const restored = await read(await call("POST", `/v1/posts/${post.id}/revisions/${first.id}/restore`, tokens.writer));
    expect(restored.title).toBe("The first title of this article, long enough to pass");
  });

  test("CMS-API-009 starts a draft from anything and names it after its heading", async () => {
    const empty = await read(await call("POST", "/v1/posts", tokens.writer, {}));
    expect(empty).toMatchObject({ status: "draft", lang: "en", slug: "untitled", title: "", markdown: "", secondaryKeywords: [] });
    const second = await read(await call("POST", "/v1/posts", tokens.writer, { lang: "en" }));
    expect(second.slug).toBe("untitled-2");
    // The draft takes its slug from the heading it gets, and its images follow.
    const named = await read(await call("PATCH", `/v1/posts/${empty.id}`, tokens.writer, {
      markdown: "# Größer denken: Diktieren für Ärzte\n\n![A screenshot of the app](media/untitled/shot.png)",
    }));
    expect(named.slug).toBe("groesser-denken-diktieren-fuer-aerzte");
    expect(named.markdown).toContain("](media/groesser-denken-diktieren-fuer-aerzte/shot.png)");
    // A later heading no longer moves it: the slug is the post's address.
    const renamed = await read(await call("PATCH", `/v1/posts/${empty.id}`, tokens.writer, { markdown: "# Another heading" }));
    expect(renamed.slug).toBe("groesser-denken-diktieren-fuer-aerzte");
    const twin = await read(await call("POST", "/v1/posts", tokens.writer, { markdown: "# Größer denken: Diktieren für Ärzte" }));
    expect(twin.slug).toBe("groesser-denken-diktieren-fuer-aerzte-2");
    const german = await read(await call("POST", "/v1/posts", tokens.writer, { lang: "de", markdown: "# Größer denken: Diktieren für Ärzte" }));
    expect(german.slug).toBe("groesser-denken-diktieren-fuer-aerzte");
    // Incomplete is fine for a draft, not for going live.
    const refused = await call("POST", `/v1/posts/${twin.id}/publish`, tokens.publisher);
    expect(refused.status).toBe(422);
    expect((await read(refused)).error.problems.join("\n")).toContain("front matter title");
  });

  test("CMS-API-009 names drafts created or titled at the same moment apart", async () => {
    // Before, concurrent writers picked the same free number and gave up after three tries.
    const created = await Promise.all(Array.from({ length: 12 }, () => call("POST", "/v1/posts", tokens.writer, { lang: "de" })));
    expect(created.map((response) => response.status)).toEqual(Array(12).fill(201));
    const drafts = await Promise.all(created.map(read));
    expect(new Set(drafts.map((post) => post.slug)).size).toBe(12);
    const titled = await Promise.all(drafts.map((post) => call("PATCH", `/v1/posts/${post.id}?autosave=true`, tokens.writer, { markdown: "# Gleichzeitig benannt" })));
    expect(titled.map((response) => response.status)).toEqual(Array(12).fill(200));
    const slugs = (await Promise.all(titled.map(read))).map((post) => post.slug).sort();
    expect(new Set(slugs).size).toBe(12);
    expect(slugs).toContain("gleichzeitig-benannt");
    expect(slugs.every((slug) => /^gleichzeitig-benannt(-\d+)?$/.test(slug))).toBe(true);
  });

  test("CMS-API-010 keeps one revision for a run of autosaves", async () => {
    const post = await draft({ slug: "autosaved", keyword: "autosaved" });
    const revisions = async () => (await read(await call("GET", `/v1/posts/${post.id}/revisions`, tokens.reader))).revisions as Array<Record<string, any>>;
    const autosave = (markdown: string, token = tokens.writer) => call("PATCH", `/v1/posts/${post.id}?autosave=true`, token, { markdown });
    await autosave("# First words");
    await autosave("# First words, then more");
    expect((await revisions()).map((revision) => [revision.autosave, revision.snapshot.markdown]))
      .toEqual([[true, "# First words, then more"], [false, validPost().markdown]]);
    // Another author, a deliberate save and a run older than ten minutes each start a new revision.
    await autosave("# By someone else", tokens.publisher);
    expect(await revisions()).toHaveLength(3);
    await call("PATCH", `/v1/posts/${post.id}`, tokens.writer, { markdown: "# Saved on purpose" });
    await autosave("# Writing again");
    expect(await revisions()).toHaveLength(5);
    await db.execute(sql`update post_revisions set created_at = now() - interval '11 minutes' where post_id = ${post.id}`);
    await autosave("# After a break");
    expect((await revisions()).filter((revision) => revision.autosave)).toHaveLength(4);
    // A live post is never autosaved: each change is a revision of its own.
    const live = await draft({ slug: "autosave-live", keyword: "autosave live" });
    await call("POST", `/v1/posts/${live.id}/publish`, tokens.publisher);
    await call("PATCH", `/v1/posts/${live.id}?autosave=true`, tokens.writer, { imageAlt: "A Mac with a dictation waveform, updated." });
    await call("PATCH", `/v1/posts/${live.id}?autosave=true`, tokens.writer, { imageAlt: "A Mac with a dictation waveform, again." });
    const { revisions: liveRevisions } = await read(await call("GET", `/v1/posts/${live.id}/revisions`, tokens.reader));
    expect(liveRevisions.map((revision: { autosave: boolean }) => revision.autosave)).toEqual([false, false, false, false]);
  });

  test("CMS-API-011 deletes a draft, but not a live post", async () => {
    const post = await draft({ slug: "thrown-away", keyword: "thrown away" });
    expect((await call("DELETE", `/v1/posts/${post.id}`, tokens.reader)).status).toBe(403);
    expect((await call("DELETE", `/v1/posts/${post.id}`, tokens.writer)).status).toBe(204);
    expect((await call("GET", `/v1/posts/${post.id}`, tokens.reader)).status).toBe(404);
    expect((await call("DELETE", `/v1/posts/${post.id}`, tokens.writer)).status).toBe(404);
    const live = await draft({ slug: "stays-up", keyword: "stays up" });
    await call("POST", `/v1/posts/${live.id}/publish`, tokens.publisher);
    const refused = await call("DELETE", `/v1/posts/${live.id}`, tokens.writer);
    expect(refused.status).toBe(409);
    expect((await read(refused)).error.code).toBe("not_a_draft");
    expect((await read(await call("GET", `/v1/posts/${live.id}`, tokens.reader))).status).toBe("published");
  });

  test("rejects requests that do not match the API", async () => {
    const response = await call("POST", "/v1/posts", tokens.writer, { slug: "Not A Slug" });
    expect(response.status).toBe(400);
    expect((await read(response)).error.code).toBe("invalid_request");
  });
});
