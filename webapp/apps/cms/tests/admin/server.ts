// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// A local CMS for the admin: its browser journeys (playwright.config.ts) and
// development (bun run dev in apps/cms-admin). It serves the built admin when
// apps/cms-admin/dist exists, and uses a fresh database
// (HUSH_TEST_DATABASE_URL), media on disk and two seeded posts. GET
// /__e2e/sign-in signs the browser in through the CMS's own session code; that
// route exists only in this test server, never in the CMS.
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createApp } from "../../src/app";
import { createSession, setSessionCookie } from "../../src/auth/sessions";
import { Hono } from "hono";
import { createDraft, publishPost } from "../../src/posts/service";
import { LocalObjectStore } from "../../src/storage/object-store";
import { createTestDatabase } from "../database";
import { validPost } from "../fixtures";

const port = Number(process.env.PORT ?? 4310);
const database = await createTestDatabase();
const cms = { db: database.db, media: new LocalObjectStore(await mkdtemp(join(tmpdir(), "hush-cms-admin-e2e-"))) };
// The admin's origin for the CSRF check: this server itself, or the Vite dev
// server in front of it (bun run dev in apps/cms-admin sets it).
const admin = {
  publicUrl: process.env.CMS_ADMIN_ORIGIN ?? `https://localhost:${port}`,
  github: { clientId: "e2e", clientSecret: "e2e" },
  allowedGithubIds: new Set([1]),
};

const live = await createDraft(cms.db, validPost({ slug: "dictate-without-cloud", keyword: "dictate without cloud" }), "e2e");
await publishPost(cms, live.id, "e2e");
await createDraft(cms.db, validPost({
  slug: "draft-in-progress", keyword: "draft in progress",
  title: "A draft that is still being written, slowly, step by step",
}), "e2e");
const app = new Hono();
app.get("/__e2e/sign-in", async (context) => {
  const session = await createSession(cms.db, { githubUserId: 1, githubLogin: "owner" });
  setSessionCookie(context, session.token, session.expiresAt);
  return context.redirect(context.req.query("to") ?? "/");
});
const adminDir = join(import.meta.dir, "../../../cms-admin/dist");
app.route("/", createApp(cms, { admin, adminDir: await Bun.file(join(adminDir, "index.html")).exists() ? adminDir : undefined }));
// HTTPS with a throwaway self-signed certificate: every browser, WebKit too,
// then keeps the __Host- session cookie exactly as on cms.behu.sh.
const certificateDir = await mkdtemp(join(tmpdir(), "hush-cms-admin-tls-"));
const openssl = Bun.spawnSync(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1", "-subj", "/CN=localhost",
  "-addext", "subjectAltName=DNS:localhost", "-keyout", join(certificateDir, "key.pem"), "-out", join(certificateDir, "cert.pem")]);
if (openssl.exitCode !== 0) throw new Error(`openssl failed: ${openssl.stderr.toString()}`);
Bun.serve({ port, fetch: app.fetch, tls: { key: Bun.file(join(certificateDir, "key.pem")), cert: Bun.file(join(certificateDir, "cert.pem")) } });
console.info(`hush CMS admin journeys on ${admin.publicUrl}`);
process.on("SIGTERM", async () => { await database.drop(); process.exit(0); });
