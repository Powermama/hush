// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The CMS runs apart from Verified Messages: it never imports the website's
// code and never reads the proof service's database URL or signing key.
import { expect, test } from "bun:test";
import { Glob } from "bun";
import { join } from "node:path";

test("the CMS stays out of the website and the proof service", async () => {
  const root = join(import.meta.dir, "../src");
  for await (const file of new Glob("**/*.ts").scan(root)) {
    const source = await Bun.file(join(root, file)).text();
    expect(source, file).not.toMatch(/from ["'][^"']*apps\/web/);
    expect(source, file).not.toMatch(/from ["']\.\.\/\.\.\/\.\.\//);
    expect(source, file).not.toMatch(/\b(DATABASE_URL|HUSH_SERVICE_PRIVATE_JWK)\b/);
  }
});
