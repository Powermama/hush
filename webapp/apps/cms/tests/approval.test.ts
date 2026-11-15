// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Agent journeys (docs/user-journeys/cms.md): every token is an agent, which
// changes what readers see only with the owner's approval.
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import sharp from "sharp";
import { createApp } from "../src/app";
import { createToken } from "../src/auth/tokens";
import { LocalObjectStore } from "../src/storage/object-store";
import { createTestDatabase, serverUrl } from "./database";
import { credentials, ownerSession, validPost } from "./fixtures";

const png = (background: string) => sharp({ create: { width: 1600, height: 400, channels: 3, background } }).png().toBuffer();

describe.skipIf(!serverUrl)("CMS approvals", () => {
  let database: Awaited<ReturnType<typeof createTestDatabase>>;
  let app: ReturnType<typeof createApp>;
  let agent = "";
  let owner = "";

  beforeAll(async () => {
    database = await createTestDatabase();
    app = createApp({ db: database.db, media: new LocalObjectStore(await mkdtemp(join(tmpdir(), "hush-cms-approval-"))) });
    // Even with every scope, a token is an agent.
    agent = await createToken(database.db, { name: "hush-seo", scopes: ["posts:read", "posts:write", "posts:publish"] });
    owner = await ownerSession(database.db);
  });
  afterAll(async () => { await database.drop(); });

  const call = async (method: string, path: string, credential: string, body?: unknown, type = "application/json") => {
    const response = await app.request(path, {
      method,
      headers: { ...credentials(credential), ...(body ? { "content-type": type } : {}) },
      body: body === undefined ? undefined : type === "application/json" ? JSON.stringify(body) : body as RequestInit["body"],
    });
    // Every call here answers with JSON.
    return { status: response.status, body: await response.json() as Record<string, any> };
  };
  const withImage = (slug: string) => validPost({
    slug, keyword: slug.replaceAll("-", " "),
    markdown: validPost().markdown.replace("## How does it work?", `![The settings](media/${slug}/settings.png "A test Mac")\n\n## How does it work?`),
  });
  const approve = (id: string, contentHash: string, credential = owner) => call("POST", `/v1/posts/${id}/approve`, credential, { contentHash });
  const upload = async (id: string, background: string) => call("PUT", `/v1/posts/${id}/media/settings.png`, agent, await png(background), "image/png");

  test("CMS-API-013 an agent schedules or publishes only what the owner approved, as it is now", async () => {
    const { body: post } = await call("POST", "/v1/posts", agent, withImage("approved-post"));
    expect((await upload(post.id, "#4a6fa5")).status).toBe(200);
    const unapproved = await call("POST", `/v1/posts/${post.id}/schedule`, agent, { publishedAt: "2099-01-01T08:00:00.000Z" });
    expect([unapproved.status, unapproved.body.error.code]).toEqual([403, "approval_required"]);
    expect((await call("POST", `/v1/posts/${post.id}/publish`, agent)).body.error.code).toBe("approval_required");

    // The owner approves the post as they reviewed it; a change made since is not approved unseen.
    const { body: reviewed } = await call("GET", `/v1/posts/${post.id}`, owner);
    expect(reviewed.approval).toBeNull();
    await call("PATCH", `/v1/posts/${post.id}`, agent, { imageAlt: "A Mac with the dictation settings open." });
    expect((await approve(post.id, reviewed.contentHash)).body.error.code).toBe("changed_since_review");
    const { body: current } = await call("GET", `/v1/posts/${post.id}`, owner);
    const approved = await approve(post.id, current.contentHash);
    expect(approved.status).toBe(200);
    expect(approved.body.approval).toMatchObject({ approvedBy: "github:owner", current: true });

    // A change to the text, or to an image, leaves the approval lapsed.
    await call("PATCH", `/v1/posts/${post.id}`, agent, { imageAlt: "A Mac with the dictation settings, changed." });
    expect((await call("GET", `/v1/posts/${post.id}`, agent)).body.approval.current).toBe(false);
    expect((await call("POST", `/v1/posts/${post.id}/publish`, agent)).body.error.code).toBe("approval_lapsed");
    await approve(post.id, (await call("GET", `/v1/posts/${post.id}`, owner)).body.contentHash);
    await upload(post.id, "#a54a4a");
    expect((await call("POST", `/v1/posts/${post.id}/publish`, agent)).body.error.code).toBe("approval_lapsed");

    await approve(post.id, (await call("GET", `/v1/posts/${post.id}`, owner)).body.contentHash);
    const scheduled = await call("POST", `/v1/posts/${post.id}/schedule`, agent, { publishedAt: "2099-01-01T08:00:00.000Z" });
    expect([scheduled.status, scheduled.body.status]).toEqual([200, "scheduled"]);
  });

  test("CMS-API-014 only the owner approves, and changes or unpublishes a live post", async () => {
    const { body: post } = await call("POST", "/v1/posts", agent, withImage("owner-only"));
    await upload(post.id, "#4a6fa5");
    const refused = await approve(post.id, post.contentHash, agent);
    expect([refused.status, refused.body.error.code]).toEqual([403, "owner_only"]);
    expect((await app.request(`/v1/posts/${post.id}/approve`, { method: "POST" })).status).toBe(401);

    const { body: reviewed } = await call("GET", `/v1/posts/${post.id}`, owner);
    await approve(post.id, reviewed.contentHash);
    expect((await call("POST", `/v1/posts/${post.id}/publish`, agent)).body.status).toBe("published");

    const edit = await call("PATCH", `/v1/posts/${post.id}`, agent, { imageAlt: "A Mac with the dictation settings, edited live." });
    expect([edit.status, edit.body.error.code]).toEqual([403, "live_post"]);
    expect((await upload(post.id, "#a54a4a")).body.error.code).toBe("live_post");
    const { body: history } = await call("GET", `/v1/posts/${post.id}/revisions`, agent);
    expect((await call("POST", `/v1/posts/${post.id}/revisions/${history.revisions.at(-1).id}/restore`, agent)).body.error.code).toBe("live_post");
    expect((await call("POST", `/v1/posts/${post.id}/unpublish`, agent)).body.error.code).toBe("owner_only");
    expect((await call("GET", `/v1/posts/${post.id}`, agent)).body.imageAlt).toBe(post.imageAlt);

    // The owner changes the live post; the change leaves the approval lapsed.
    const ownerEdit = await call("PATCH", `/v1/posts/${post.id}`, owner, { imageAlt: "A Mac with the dictation settings, edited by the owner." });
    expect([ownerEdit.status, ownerEdit.body.approval.current]).toEqual([200, false]);
    expect((await call("POST", `/v1/posts/${post.id}/unpublish`, owner)).body.status).toBe("draft");
    // Back as a draft, the agent may work on it again.
    expect((await call("PATCH", `/v1/posts/${post.id}`, agent, { imageAlt: "A Mac with the dictation settings, a draft again." })).status).toBe(200);
  });
});
