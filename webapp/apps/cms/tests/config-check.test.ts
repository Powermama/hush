// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// CMS-CONFIG-001 (docs/user-journeys/cms.md): an instance with credentials that
// do not work never reports ready, so a rolling update keeps the old one.
import { expect, test } from "bun:test";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { githubClientCheck, storeCheck, watchConfiguration } from "../src/config-check";
import { healthRoutes } from "../src/routes/health";
import { LocalObjectStore, type ObjectStore } from "../src/storage/object-store";

const admin = { publicUrl: "https://cms.behu.sh", github: { clientId: "id", clientSecret: "secret" }, allowedGithubIds: new Set([1]) };
const github = (answer: unknown) => (async () => Response.json(answer)) as unknown as typeof fetch;

test("CMS-CONFIG-001 a bucket that refuses the credentials keeps the CMS not ready, and it becomes ready once they work", async () => {
  let working = false;
  const store = { list: async () => { if (!working) throw new Error("S3Error: Please use AWS4-HMAC-SHA256"); return []; } } as unknown as ObjectStore;
  const logged: string[] = [];
  const watch = watchConfiguration([storeCheck("media bucket", store)], { retryMs: 20, log: (_message, details) => logged.push(String(details.check)) });
  await watch.started;
  expect(watch.configured()).toBe(false);
  expect(logged).toEqual(["media bucket"]);
  // Readiness answers 503 before any database query is even made.
  const health = healthRoutes({} as never, () => false, watch.configured);
  expect((await health.request("/health/ready")).status).toBe(503);
  working = true;
  await Bun.sleep(80);
  expect(watch.configured()).toBe(true);
  watch.stop();

  const local = watchConfiguration([storeCheck("local", new LocalObjectStore(await mkdtemp(join(tmpdir(), "hush-cms-check-"))))]);
  await local.started;
  expect(local.configured()).toBe(true);
});

test("CMS-CONFIG-001 a GitHub client secret that GitHub refuses keeps the CMS not ready; an unreachable GitHub does not", async () => {
  await expect(githubClientCheck(admin, github({ error: "incorrect_client_credentials" })).run()).rejects.toThrow("GitHub refuses");
  await githubClientCheck(admin, github({ error: "bad_verification_code" })).run();
  await githubClientCheck(admin, (async () => { throw new TypeError("fetch failed"); }) as unknown as typeof fetch).run();
});
