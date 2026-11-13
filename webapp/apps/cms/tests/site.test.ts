// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// CMS-SITE journeys (docs/user-journeys/cms.md): the export the website builds
// from, the site revision and the deploy loop.
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { parseArticle, renderArticle } from "@hush/article";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createApp } from "../src/app";
import { createToken } from "../src/auth/tokens";
import type { SiteConfig } from "../src/config";
import { siteChanges, siteState } from "../src/db/schema";
import { publishDuePosts } from "../src/posts/service";
import { deployWindowMs, syncSite } from "../src/site/deploy";
import { LocalObjectStore } from "../src/storage/object-store";
import { createTestDatabase, serverUrl } from "./database";
import { validPost } from "./fixtures";
import { png } from "./media.test";

const site: SiteConfig = {
  url: "https://behu.sh",
  coolify: { url: "https://coolify.example", token: "deploy-only", websiteUuid: "website-uuid" },
  indexNowKey: "0123456789abcdef0123456789abcdef",
};

/** A stand-in for the live site, Coolify and IndexNow that records every call. */
function fakeInternet(initialRevision: number | null) {
  const state = { revision: initialRevision, indexNowStatus: 202, calls: [] as Array<{ url: string; body?: unknown; authorization?: string }> };
  const fetcher = async (url: string, init?: RequestInit) => {
    const headers = new Headers(init?.headers);
    state.calls.push({ url, body: init?.body ? JSON.parse(String(init.body)) : undefined, authorization: headers.get("authorization") ?? undefined });
    if (url === "https://behu.sh/blog/revision.txt") {
      return state.revision === null ? new Response("Not found", { status: 404 }) : new Response(`${state.revision}\n`);
    }
    if (url === "https://coolify.example/api/v1/deploy") return Response.json({ deployments: [] });
    if (url === "https://api.indexnow.org/indexnow") return new Response(null, { status: state.indexNowStatus });
    throw new Error(`Unexpected request to ${url}`);
  };
  return { state, fetcher };
}

describe.skipIf(!serverUrl)("CMS site", () => {
  let database: Awaited<ReturnType<typeof createTestDatabase>>;
  let app: ReturnType<typeof createApp>;
  let owner = "";
  let reader = "";
  let store: LocalObjectStore;

  beforeAll(async () => {
    database = await createTestDatabase();
    store = new LocalObjectStore(await mkdtemp(join(tmpdir(), "hush-cms-media-")));
    app = createApp({ db: database.db, media: store });
    owner = await createToken(database.db, { name: "owner", scopes: ["posts:read", "posts:write", "posts:publish"] });
    reader = await createToken(database.db, { name: "website-build", scopes: ["posts:read"] });
  });
  afterAll(async () => { await database?.drop(); });

  const call = (method: string, path: string, body?: RequestInit["body"], type = "application/json", token = owner) => app.request(path, {
    method, body, headers: { authorization: `Bearer ${token}`, ...(body ? { "content-type": type } : {}) },
  });
  const read = (response: Response) => response.json() as Promise<Record<string, any>>;
  const revision = async () => (await database.db.select().from(siteState))[0]!.revision;
  const changedPaths = async (after: number) => (await database.db.select().from(siteChanges))
    .filter((row) => row.revision > after).map((row) => row.path).sort();

  test("CMS-SITE-001 exports published posts as hush-seo files that render exactly like the stored post", async () => {
    const markdown = validPost().markdown.replace("## How does it work?",
      '![The Dictation settings on a Mac](media/exported/settings.png)\n\n## How does it work?');
    const post = await read(await call("POST", "/v1/posts", JSON.stringify(validPost({ slug: "exported", keyword: "exported guide", markdown }))));
    await call("PUT", `/v1/posts/${post.id}/media/settings.png`, await png(1400), "image/png");
    const published = await read(await call("POST", `/v1/posts/${post.id}/publish`));
    await call("POST", "/v1/posts", JSON.stringify(validPost({ slug: "still-a-draft", keyword: "still a draft" })));

    expect((await call("GET", "/v1/site/export", undefined, undefined, "nope")).status).toBe(401);
    const revisionResponse = await app.request("/v1/site/revision");
    expect(revisionResponse.headers.get("cache-control")).toBe("no-store");
    expect(Number(await revisionResponse.text())).toBe(await revision());
    const exported = await read(await call("GET", "/v1/site/export", undefined, undefined, reader));
    expect(exported.revision).toBe(await revision());
    expect(exported.files.map((file: { path: string }) => file.path)).toEqual(["en/exported.md"]);

    const [file] = exported.files;
    const { article, problems } = parseArticle(file.markdown);
    expect(problems).toEqual([]);
    expect(article!.front).toMatchObject({ slug: "exported", draft: false, published: published.publishedAt.slice(0, 10), schema: ["BlogPosting"] });
    expect(article!.front.secondaryKeywords).toEqual(["offline dictation mac", "local speech to text"]);
    expect(article!.body).toBe(markdown);

    // The image original comes back byte for byte, and the file renders to the stored HTML.
    expect(file.media).toEqual([{ path: "en/media/exported/settings.png", sha256: expect.stringMatching(/^[0-9a-f]{64}$/), contentType: "image/png" }]);
    const original = await call("GET", `/v1/media/${file.media[0].sha256}`, undefined, undefined, reader);
    expect(original.headers.get("content-type")).toBe("image/png");
    const bytes = new Uint8Array(await original.arrayBuffer());
    expect(Buffer.from(bytes).equals(await png(1400))).toBe(true);
    const rendered = await renderArticle(article!, {
      knownPaths: new Set(["/", "/blog", "/blog/exported", "/blog/authors/clemens-kressmann"]),
      coverSeed: [],
      loadImage: async () => ({ bytes, source: "original" }),
    });
    expect(rendered.problems).toEqual([]);
    expect(rendered.post!.html).toBe(published.rendition.html);
    expect((await call("GET", `/v1/media/${"0".repeat(64)}`, undefined, undefined, reader)).status).toBe(404);
  });

  test("CMS-SITE-002 every change to a public page takes the next site revision; draft edits do not", async () => {
    const draft = await read(await call("POST", "/v1/posts", JSON.stringify(validPost({ slug: "revisioned", keyword: "revisioned guide" }))));
    let before = await revision();
    await call("PATCH", `/v1/posts/${draft.id}`, JSON.stringify({ title: "How to dictate on a Mac without the cloud, a full guide" }));
    expect(await revision()).toBe(before);

    await call("POST", `/v1/posts/${draft.id}/publish`);
    expect(await revision()).toBe(before + 1);
    expect(await changedPaths(before)).toEqual(["/blog", "/blog/revisioned"]);

    before = await revision();
    await call("PATCH", `/v1/posts/${draft.id}`, JSON.stringify({ slug: "renamed" }));
    expect(await changedPaths(before)).toEqual(["/blog", "/blog/renamed", "/blog/revisioned"]);

    before = await revision();
    await call("POST", `/v1/posts/${draft.id}/unpublish`);
    expect(await changedPaths(before)).toEqual(["/blog", "/blog/renamed"]);

    // A scheduled post changes the site only when it goes live.
    const scheduled = await read(await call("POST", "/v1/posts", JSON.stringify(validPost({ lang: "de", slug: "geplant", keyword: "geplanter artikel", markdown: validPost().markdown.replace("## Frequently asked questions", "## Häufige Fragen") }))));
    const response = await read(await call("POST", `/v1/posts/${scheduled.id}/schedule`, JSON.stringify({ publishedAt: new Date(Date.now() + 2_000).toISOString() })));
    expect(response.error ?? response.status).toBe("scheduled");
    before = await revision();
    await Bun.sleep(2_100);
    expect((await publishDuePosts(database.db)).map((post) => post.slug)).toEqual(["geplant"]);
    expect(await changedPaths(before)).toEqual(["/de/blog", "/de/blog/geplant"]);
  });

  test("CMS-SITE-003 a site behind the CMS gets one deploy per window, and live changes go to IndexNow", async () => {
    const internet = fakeInternet(null);
    const target = await revision();
    const start = new Date();

    // The site was built without the CMS: deploy once, then wait for it.
    let result = await syncSite(database.db, site, internet.fetcher, start);
    expect(result).toEqual({ live: 0, notified: [], deployRequested: true });
    const deploy = internet.state.calls.find((call) => call.url === "https://coolify.example/api/v1/deploy")!;
    expect(deploy).toMatchObject({ authorization: "Bearer deploy-only", body: { uuid: "website-uuid", force: false } });
    result = await syncSite(database.db, site, internet.fetcher, new Date(start.getTime() + 60_000));
    expect(result.deployRequested).toBe(false);

    // The build is live: every changed page is submitted once, the deploy is done.
    internet.state.revision = target;
    result = await syncSite(database.db, site, internet.fetcher, new Date(start.getTime() + 180_000));
    expect(result.deployRequested).toBe(false);
    expect(result.notified).toEqual([
      "https://behu.sh/blog", "https://behu.sh/blog/exported", "https://behu.sh/blog/renamed", "https://behu.sh/blog/revisioned",
      "https://behu.sh/de/blog", "https://behu.sh/de/blog/geplant",
    ]);
    const submission = internet.state.calls.find((call) => call.url === "https://api.indexnow.org/indexnow")!;
    expect(submission.body).toEqual({
      host: "behu.sh", key: site.indexNowKey, keyLocation: `https://behu.sh/${site.indexNowKey}.txt`, urlList: result.notified,
    });
    internet.state.calls.length = 0;
    expect(await syncSite(database.db, site, internet.fetcher, new Date(start.getTime() + 240_000))).toEqual({ live: target, notified: [], deployRequested: false });
    expect(internet.state.calls.map((call) => call.url)).toEqual(["https://behu.sh/blog/revision.txt"]);

    // A deploy that never shows up is asked for again after the window.
    const draft = await read(await call("POST", "/v1/posts", JSON.stringify(validPost({ slug: "late", keyword: "late guide" }))));
    await call("POST", `/v1/posts/${draft.id}/publish`);
    const later = start.getTime() + 300_000;
    expect((await syncSite(database.db, site, internet.fetcher, new Date(later))).deployRequested).toBe(true);
    expect((await syncSite(database.db, site, internet.fetcher, new Date(later + deployWindowMs - 1))).deployRequested).toBe(false);
    expect((await syncSite(database.db, site, internet.fetcher, new Date(later + deployWindowMs))).deployRequested).toBe(true);
  });

  test("CMS-SITE-004 IndexNow outages are retried; refusals are logged once and not retried", async () => {
    const internet = fakeInternet(await revision());
    const draft = await read(await call("POST", "/v1/posts", JSON.stringify(validPost({ slug: "notified", keyword: "notified guide" }))));
    await call("POST", `/v1/posts/${draft.id}/publish`);
    internet.state.revision = await revision();
    const notified = async () => (await database.db.select().from(siteState))[0]!.notifiedRevision;

    internet.state.indexNowStatus = 503;
    await expect(syncSite(database.db, site, internet.fetcher)).rejects.toThrow("IndexNow answered 503");
    expect(await notified()).toBeLessThan(internet.state.revision);

    internet.state.indexNowStatus = 403;
    const result = await syncSite(database.db, site, internet.fetcher);
    expect(result.notified).toContain("https://behu.sh/blog/notified");
    expect(await notified()).toBe(internet.state.revision);
  });
});
