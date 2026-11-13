// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// CMS media journeys (docs/user-journeys/cms.md) through the HTTP API.
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import sharp from "sharp";
import { createApp } from "../src/app";
import { createToken } from "../src/auth/tokens";
import { LocalObjectStore } from "../src/storage/object-store";
import { createTestDatabase, serverUrl } from "./database";
import { validPost } from "./fixtures";

export const png = (width: number, height = 400) =>
  sharp({ create: { width, height, channels: 3, background: "#4a6fa5" } }).png().toBuffer();

describe.skipIf(!serverUrl)("CMS media", () => {
  let database: Awaited<ReturnType<typeof createTestDatabase>>;
  let app: ReturnType<typeof createApp>;
  let store: LocalObjectStore;
  let token = "";

  beforeAll(async () => {
    database = await createTestDatabase();
    store = new LocalObjectStore(await mkdtemp(join(tmpdir(), "hush-cms-media-")));
    app = createApp({ db: database.db, media: store });
    token = await createToken(database.db, { name: "owner", scopes: ["posts:read", "posts:write", "posts:publish"] });
  });
  afterAll(async () => { await database?.drop(); });

  const call = (method: string, path: string, body?: RequestInit["body"], type = "application/json") => app.request(path, {
    method, body, headers: { authorization: `Bearer ${token}`, ...(body ? { "content-type": type } : {}) },
  });
  const read = (response: Response) => response.json() as Promise<Record<string, any>>;

  test("CMS-MEDIA-001 publishes an article with its image as responsive WebP", async () => {
    const markdown = validPost().markdown.replace("## How does it work?",
      '![The Dictation settings on a Mac](media/with-image/dictation-settings.png "Our test Mac")\n\n## How does it work?');
    const post = await read(await call("POST", "/v1/posts", JSON.stringify(validPost({ slug: "with-image", keyword: "with image", markdown }))));
    const missing = await read(await call("POST", `/v1/posts/${post.id}/publish`));
    expect(missing.error.problems).toContain('image "media/with-image/dictation-settings.png" does not exist');

    const upload = await call("PUT", `/v1/posts/${post.id}/media/dictation-settings.png`, await png(1600), "image/png");
    expect(upload.status).toBe(200);
    expect(await read(upload)).toMatchObject({ name: "dictation-settings.png", width: 1600, height: 400, contentType: "image/png" });

    const published = await read(await call("POST", `/v1/posts/${post.id}/publish`));
    expect(published.status).toBe("published");
    const html: string = published.rendition.html;
    expect(html).toContain("<figure>");
    expect(html).toContain('alt="The Dictation settings on a Mac"');
    const paths = [...html.matchAll(/\/blog\/media\/[a-z0-9-]+\.webp/g)].map((match) => match[0]);
    expect(paths.some((path) => path.endsWith("-680.webp"))).toBe(true);
    expect(paths.some((path) => path.endsWith("-1360.webp"))).toBe(true);
    for (const path of new Set(paths)) {
      const bytes = await store.get(path.slice(1));
      expect(bytes, path).toBeDefined();
      const { format, width } = await sharp(bytes!).metadata();
      expect(format).toBe("webp");
      expect(path.endsWith(`-${width}.webp`)).toBe(true);
    }
  });

  test("CMS-MEDIA-002 refuses files that are not what they claim to be", async () => {
    const post = await read(await call("POST", "/v1/posts", JSON.stringify(validPost({ slug: "bad-media", keyword: "bad media" }))));
    const cases: Array<[string, RequestInit["body"], string, string]> = [
      ["Bad Name.png", await png(800), "image/png", "invalid_name"],
      ["shot.png", await png(800), "image/jpeg", "invalid_type"],
      ["shot.png", new TextEncoder().encode("<svg></svg>"), "image/png", "unreadable_image"],
    ];
    for (const [name, body, type, code] of cases) {
      const response = await call("PUT", `/v1/posts/${post.id}/media/${encodeURIComponent(name)}`, body, type);
      expect(response.status, code).toBe(422);
      expect((await read(response)).error.code).toBe(code);
    }
    const tooLarge = await call("PUT", `/v1/posts/${post.id}/media/huge.png`, new Uint8Array(10 * 1024 * 1024 + 1), "image/png");
    expect(tooLarge.status).toBe(413);
    expect((await read(await call("GET", `/v1/posts/${post.id}/media`))).media).toEqual([]);
  });
});
