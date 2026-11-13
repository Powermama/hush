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

  test("rejects requests that do not match the API", async () => {
    const response = await call("POST", "/v1/posts", tokens.writer, { slug: "Not A Slug" });
    expect(response.status).toBe(400);
    expect((await read(response)).error.code).toBe("invalid_request");
  });
});
