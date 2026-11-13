// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { afterAll, beforeAll, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { mkdtemp, readFile, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pullFromCms } from "./pull-cms";

const image = new Uint8Array([137, 80, 78, 71, 1, 2, 3]);
const sha256 = createHash("sha256").update(image).digest("hex");
const exported = {
  revision: 7,
  files: [{
    path: "en/a-guide.md",
    markdown: "---\nslug: \"a-guide\"\n---\n# A guide\n",
    media: [{ path: "en/media/a-guide/shot.png", sha256, contentType: "image/png" }],
  }],
};

let server: ReturnType<typeof Bun.serve>;
let served: { export: unknown; image: Uint8Array<ArrayBuffer> } = { export: exported, image };
const dirs: string[] = [];
const emptyDir = async () => { const dir = await mkdtemp(join(tmpdir(), "hush-pull-cms-")); dirs.push(dir); return dir; };

beforeAll(() => {
  server = Bun.serve({
    port: 0,
    fetch(request) {
      if (request.headers.get("authorization") !== "Bearer build-token") return new Response("no", { status: 401 });
      const { pathname } = new URL(request.url);
      if (pathname === "/v1/site/export") return Response.json(served.export);
      if (pathname === `/v1/media/${sha256}`) return new Response(served.image);
      return new Response("missing", { status: 404 });
    },
  });
});
afterAll(async () => {
  server.stop(true);
  for (const dir of dirs) await rm(dir, { recursive: true, force: true });
});

test("writes published articles, their verified images and the site revision in the hush-seo layout", async () => {
  served = { export: exported, image };
  const dir = await emptyDir();
  expect(await pullFromCms({ url: server.url.toString(), token: "build-token", dir })).toEqual({ revision: 7, articles: 1, images: 1 });
  expect(await readFile(join(dir, "en/a-guide.md"), "utf8")).toBe(exported.files[0]!.markdown);
  expect(new Uint8Array(await readFile(join(dir, "en/media/a-guide/shot.png")))).toEqual(image);
  expect(await readFile(join(dir, "revision.txt"), "utf8")).toBe("7\n");
});

test("fails closed: a refused token, a malformed export or a corrupted image stop the build", async () => {
  served = { export: exported, image };
  await expect(pullFromCms({ url: server.url.toString(), token: "wrong", dir: await emptyDir() })).rejects.toThrow("401");
  served = { export: { ...exported, files: [{ ...exported.files[0], path: "../escape.md" }] }, image };
  await expect(pullFromCms({ url: server.url.toString(), token: "build-token", dir: await emptyDir() })).rejects.toThrow();
  served = { export: exported, image: new Uint8Array([1, 2, 3]) };
  const dir = await emptyDir();
  await expect(pullFromCms({ url: server.url.toString(), token: "build-token", dir })).rejects.toThrow("does not match its hash");
  expect(await readdir(dir, { recursive: true })).not.toContain("revision.txt");
});
