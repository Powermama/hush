// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { expect, test } from "bun:test";
import { mkdir, mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

test("a failed social preview render leaves the previously generated site untouched", async () => {
  const dir = await mkdtemp(join(tmpdir(), "hush-blog-generation-test-"));
  const existing = new Map([
    ["shared/blog-posts.generated.ts", "previous metadata"],
    ["src/blog/generated/routes.generated.tsx", "previous routes"],
    ["src/blog/generated/en/previous.tsx", "previous article"],
    ["public/blog/feed.xml", "previous feed"],
    ["public/blog/covers/previous-social.png", "previous cover"],
  ]);
  try {
    for (const [path, content] of existing) {
      await mkdir(dirname(join(dir, path)), { recursive: true });
      await writeFile(join(dir, path), content);
    }
    const process = Bun.spawn([Bun.which("bun")!, join(import.meta.dir, "generate-blog.ts")], {
      cwd: dir,
      env: {
        ...Bun.env,
        HUSH_BLOG_CONTENT_DIR: join(import.meta.dir, "fixtures/content"),
        PLAYWRIGHT_BROWSERS_PATH: join(dir, "missing-browsers"),
      },
      stdout: "pipe", stderr: "pipe",
    });
    const [exitCode, stderr] = await Promise.all([process.exited, new Response(process.stderr).text()]);
    expect(exitCode).not.toBe(0);
    expect(stderr).toContain("Executable doesn't exist");
    for (const [path, content] of existing) expect(await readFile(join(dir, path), "utf8")).toBe(content);
    const files = (await readdir(dir, { recursive: true, withFileTypes: true }))
      .filter((entry) => entry.isFile());
    expect(files).toHaveLength(existing.size);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
