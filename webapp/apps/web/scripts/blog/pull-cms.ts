// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Writes the CMS's published posts into a content directory in the hush-seo
// layout (<lang>/<slug>.md, <lang>/media/<slug>/<name>) plus revision.txt, so
// the blog generator builds them exactly as it builds files from the repo.
// Fails on any problem: a build must never ship an empty or partial blog.
//
//   HUSH_CMS_URL=http://127.0.0.1:3100 HUSH_CMS_TOKEN=... bun scripts/blog/pull-cms.ts <dir>
import { createHash } from "node:crypto";
import { mkdir, readdir, writeFile } from "node:fs/promises";
import { dirname, join, normalize } from "node:path";
import { z } from "zod";

const exportSchema = z.object({
  revision: z.number().int().nonnegative(),
  files: z.array(z.object({
    path: z.string().regex(/^(en|de)\/[a-z0-9]+(-[a-z0-9]+)*\.md$/),
    markdown: z.string().min(1),
    media: z.array(z.object({
      path: z.string().regex(/^(en|de)\/media\/[a-z0-9]+(-[a-z0-9]+)*\/[a-z0-9]+(-[a-z0-9]+)*\.(png|jpe?g|webp)$/),
      sha256: z.string().regex(/^[0-9a-f]{64}$/),
      contentType: z.string(),
    })),
  })),
});

export async function pullFromCms(options: { url: string; token: string; dir: string; fetcher?: typeof fetch }) {
  const fetcher = options.fetcher ?? fetch;
  const get = async (path: string) => {
    const response = await fetcher(new URL(path, options.url), {
      headers: { authorization: `Bearer ${options.token}` }, signal: AbortSignal.timeout(30_000),
    });
    if (!response.ok) throw new Error(`The CMS answered ${response.status} for ${path}`);
    return response;
  };
  if ((await readdir(options.dir).catch(() => [])).length) throw new Error(`${options.dir} must be empty`);

  const site = exportSchema.parse(await (await get("/v1/site/export")).json());
  const write = async (path: string, data: string | Uint8Array) => {
    const target = join(options.dir, normalize(path));
    await mkdir(dirname(target), { recursive: true });
    await writeFile(target, data);
  };
  let images = 0;
  for (const file of site.files) {
    await write(file.path, file.markdown);
    for (const image of file.media) {
      const bytes = new Uint8Array(await (await get(`/v1/media/${image.sha256}`)).arrayBuffer());
      if (createHash("sha256").update(bytes).digest("hex") !== image.sha256) throw new Error(`${image.path} does not match its hash`);
      await write(image.path, bytes);
      images += 1;
    }
  }
  await write("revision.txt", `${site.revision}\n`);
  return { revision: site.revision, articles: site.files.length, images };
}

if (import.meta.main) {
  const dir = Bun.argv[2];
  const url = process.env.HUSH_CMS_URL;
  const token = process.env.HUSH_CMS_TOKEN;
  if (!dir || !url || !token) {
    console.error("Usage: HUSH_CMS_URL=... HUSH_CMS_TOKEN=... bun scripts/blog/pull-cms.ts <empty directory>");
    process.exit(1);
  }
  const result = await pullFromCms({ url, token, dir });
  console.info(`Pulled ${result.articles} published article${result.articles === 1 ? "" : "s"} and ${result.images} image${result.images === 1 ? "" : "s"} at site revision ${result.revision}.`);
}
