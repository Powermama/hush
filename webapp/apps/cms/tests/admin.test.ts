// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// CMS-ADMIN journeys (docs/user-journeys/cms.md): GitHub sign-in, sessions,
// CSRF, the preview and the admin served on the CMS origin. There is no test
// login: sessions are created through the same function the callback uses.
import { afterAll, afterEach, beforeAll, describe, expect, test } from "bun:test";
import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createApp } from "../src/app";
import { createSession, sessionCookie } from "../src/auth/sessions";
import { loadConfig, type AdminConfig } from "../src/config";
import { eq } from "drizzle-orm";
import { hashToken } from "../src/auth/hash";
import { adminSessions } from "../src/db/schema";
import { listRevisions } from "../src/posts/service";
import { LocalObjectStore } from "../src/storage/object-store";
import { createTestDatabase, serverUrl } from "./database";
import { validPost } from "./fixtures";

const admin: AdminConfig = {
  publicUrl: "https://cms.behu.sh",
  github: { clientId: "client-id", clientSecret: "client-secret" },
  allowedGithubIds: new Set([4242]),
};
const origin = admin.publicUrl;
const realFetch = globalThis.fetch;

/** GitHub's token endpoint and /user, answering as the given account; the token request must carry the PKCE verifier. */
function fakeGitHub(user: { id: number; login: string }, verifier?: string) {
  globalThis.fetch = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input instanceof Request ? input.url : input);
    if (url.startsWith("https://github.com/login/oauth/access_token")) {
      const body = new URLSearchParams(await (input instanceof Request ? input.text() : String(init?.body ?? "")));
      if (verifier !== undefined) expect(body.get("code_verifier")).toBe(verifier);
      return Response.json({ access_token: "gho_test", token_type: "bearer", scope: "" });
    }
    if (url === "https://api.github.com/user") {
      expect(new Headers(init?.headers).get("authorization")).toBe("Bearer gho_test");
      return Response.json(user);
    }
    return realFetch(input, init);
  }) as typeof fetch;
}

describe.skipIf(!serverUrl)("CMS admin", () => {
  let database: Awaited<ReturnType<typeof createTestDatabase>>;
  let app: ReturnType<typeof createApp>;
  let adminDir = "";

  beforeAll(async () => {
    database = await createTestDatabase();
    adminDir = await mkdtemp(join(tmpdir(), "hush-cms-admin-"));
    await mkdir(join(adminDir, "assets"), { recursive: true });
    await writeFile(join(adminDir, "index.html"), "<!doctype html><title>hush CMS</title><div id=root></div>");
    await writeFile(join(adminDir, "assets", "app-abc123.js"), "console.log('admin')");
    const media = new LocalObjectStore(await mkdtemp(join(tmpdir(), "hush-cms-media-")));
    app = createApp({ db: database.db, media }, { admin, adminDir });
  });
  afterEach(() => { globalThis.fetch = realFetch; });
  afterAll(async () => { await database?.drop(); });

  const cookieOf = (response: Response, name: string) =>
    response.headers.getSetCookie().find((cookie) => cookie.startsWith(`${name}=`));
  const signedIn = async (login = "owner") => {
    const { token } = await createSession(database.db, { githubUserId: 4242, githubLogin: login });
    return `${sessionCookie}=${token}`;
  };
  const call = (method: string, path: string, cookie: string, body?: unknown) => app.request(path, {
    method,
    headers: { cookie, origin, ...(body ? { "content-type": "application/json" } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });

  test("CMS-ADMIN-001 sign-in goes to GitHub with a state that the callback must return", async () => {
    const start = await app.request("/auth/github");
    expect(start.status).toBe(302);
    const location = new URL(start.headers.get("location")!);
    expect(location.origin + location.pathname).toBe("https://github.com/login/oauth/authorize");
    expect(location.searchParams.get("redirect_uri")).toBe("https://cms.behu.sh/auth/github/callback");
    expect(location.searchParams.get("scope")).toBeNull();
    // PKCE (RFC 7636, S256), as RFC 9700 recommends for confidential clients.
    expect(location.searchParams.get("code_challenge_method")).toBe("S256");
    const verifier = cookieOf(start, "__Host-cms_oauth_verifier")!.split(";")[0]!.split("=")[1]!;
    const challenge = new Bun.CryptoHasher("sha256").update(verifier).digest("base64url");
    expect(location.searchParams.get("code_challenge")).toBe(challenge);
    const state = location.searchParams.get("state")!;
    const stateCookie = cookieOf(start, "__Host-cms_oauth_state")!;
    expect(stateCookie).toContain(`=${state}`);
    expect(stateCookie).toContain("HttpOnly");
    expect(stateCookie).toContain("Secure");
    expect(stateCookie).toContain("SameSite=Lax");

    fakeGitHub({ id: 4242, login: "owner" }, verifier);
    const flow = `__Host-cms_oauth_state=${state}; __Host-cms_oauth_verifier=${verifier}`;
    const forged = await app.request(`/auth/github/callback?code=c&state=other`, { headers: { cookie: flow } });
    expect(forged.status).toBe(400);
    expect(cookieOf(forged, sessionCookie)).toBeUndefined();

    const noVerifier = await app.request(`/auth/github/callback?code=c&state=${state}`, { headers: { cookie: `__Host-cms_oauth_state=${state}` } });
    expect(noVerifier.status).toBe(400);
    const callback = await app.request(`/auth/github/callback?code=c&state=${state}`, { headers: { cookie: flow } });
    expect(callback.status).toBe(302);
    expect(callback.headers.get("location")).toBe("/");
    const session = cookieOf(callback, sessionCookie)!;
    for (const attribute of ["HttpOnly", "Secure", "SameSite=Lax", "Path=/"]) expect(session).toContain(attribute);
    const [row] = await database.db.select().from(adminSessions);
    expect(row).toMatchObject({ githubUserId: 4242, githubLogin: "owner" });
    expect(session).not.toContain(row!.tokenHash);
  });

  test("CMS-ADMIN-002 GitHub accounts outside the allowlist get no session", async () => {
    const start = await app.request("/auth/github");
    const state = new URL(start.headers.get("location")!).searchParams.get("state")!;
    fakeGitHub({ id: 9999, login: "stranger" });
    const verifier = cookieOf(start, "__Host-cms_oauth_verifier")!.split(";")[0]!.split("=")[1]!;
    const callback = await app.request(`/auth/github/callback?code=c&state=${state}`, { headers: { cookie: `__Host-cms_oauth_state=${state}; __Host-cms_oauth_verifier=${verifier}` } });
    expect(callback.status).toBe(403);
    expect(cookieOf(callback, sessionCookie)).toBeUndefined();
  });

  test("CMS-ADMIN-003 a session acts as the owner and is recorded by login; signing out ends it", async () => {
    const cookie = await signedIn("clemens");
    expect(await (await call("GET", "/auth/session", cookie)).json()).toEqual({ login: "clemens" });
    const post = await (await call("POST", "/v1/posts", cookie, validPost({ slug: "from-admin", keyword: "from admin" }))).json() as { id: string };
    expect((await call("POST", `/v1/posts/${post.id}/publish`, cookie)).status).toBe(200);
    expect((await listRevisions(database.db, post.id)).map((revision) => revision.actor)).toEqual(["github:clemens", "github:clemens"]);

    const signOut = await call("POST", "/auth/sign-out", cookie);
    expect(signOut.status).toBe(204);
    expect(signOut.headers.get("clear-site-data")).toBe('"cache", "cookies", "storage"');
    expect((await call("GET", "/v1/posts", cookie)).status).toBe(401);
    expect((await call("GET", "/auth/session", cookie)).status).toBe(401);
  });

  test("CMS-ADMIN-004 expired and idle sessions and cross-site writes are refused", async () => {
    const { token } = await createSession(database.db, { githubUserId: 4242, githubLogin: "owner" }, new Date(Date.now() - 8 * 86_400_000));
    expect((await call("GET", "/v1/posts", `${sessionCookie}=${token}`)).status).toBe(401);

    // Idle for longer than 12 hours ends the session, even within its week.
    const idle = await createSession(database.db, { githubUserId: 4242, githubLogin: "owner" });
    await database.db.update(adminSessions).set({ lastSeenAt: new Date(Date.now() - 13 * 3_600_000) }).where(eq(adminSessions.tokenHash, hashToken(idle.token)));
    expect((await call("GET", "/v1/posts", `${sessionCookie}=${idle.token}`)).status).toBe(401);

    const cookie = await signedIn();
    const crossSite = await app.request("/auth/sign-out", { method: "POST", headers: { cookie, origin: "https://evil.example", "content-type": "application/x-www-form-urlencoded" } });
    expect(crossSite.status).toBe(403);
    expect((await call("GET", "/auth/session", cookie)).status).toBe(200);
  });

  test("CMS-ADMIN-005 the preview renders unsaved changes with the contract's problems and saves nothing", async () => {
    const cookie = await signedIn();
    const post = await (await call("POST", "/v1/posts", cookie, validPost({ slug: "previewed", keyword: "previewed guide" }))).json() as { id: string };
    const before = (await listRevisions(database.db, post.id)).length;
    const preview = await (await call("POST", `/v1/posts/${post.id}/preview`, cookie, { markdown: `${validPost().markdown}\n\nAn edit nobody saved.` })).json() as {
      problems: string[]; rendition: { html: string } | null;
    };
    expect(preview.problems).toEqual([]);
    expect(preview.rendition!.html).toContain("An edit nobody saved.");
    const broken = await (await call("POST", `/v1/posts/${post.id}/preview`, cookie, { markdown: "# Only a heading" })).json() as { problems: string[] };
    expect(broken.problems.length).toBeGreaterThan(0);
    expect((await listRevisions(database.db, post.id)).length).toBe(before);
    expect((await (await call("GET", `/v1/posts/${post.id}`, cookie)).json() as { markdown: string }).markdown).toBe(validPost().markdown);
  });

  test("CMS-ADMIN-006 the admin is served on the CMS origin without shadowing the API, and is never indexed", async () => {
    const home = await app.request("/");
    expect(await home.text()).toContain("<title>hush CMS</title>");
    expect(home.headers.get("x-robots-tag")).toBe("noindex, nofollow");
    expect(await (await app.request("/posts/some-id")).text()).toContain("<title>hush CMS</title>");
    const asset = await app.request("/assets/app-abc123.js");
    expect(asset.headers.get("cache-control")).toBe("public, max-age=31536000, immutable");
    expect((await app.request("/v1/posts")).status).toBe(401);
    expect((await app.request("/health/live")).status).toBe(200);
    expect(await (await app.request("/robots.txt")).text()).toBe("User-agent: *\nDisallow: /\n");
    expect(await (await app.request("/..%2f..%2fpackage.json")).text()).toContain("<title>hush CMS</title>");
  });

  test("CMS-ADMIN-007 sign-in is configured completely or not at all", () => {
    const base = { CMS_DATABASE_URL: "postgresql://x", NODE_ENV: "test" };
    expect(loadConfig(base).admin).toBeUndefined();
    expect(() => loadConfig({ ...base, CMS_PUBLIC_URL: "https://cms.behu.sh" })).toThrow("CMS_ADMIN_GITHUB_IDS");
    expect(() => loadConfig({ ...base, CMS_PUBLIC_URL: "https://cms.behu.sh", CMS_ADMIN_GITHUB_IDS: "owner" })).toThrow("numeric");
    expect(() => loadConfig({ ...base, CMS_PUBLIC_URL: "http://cms.behu.sh", CMS_ADMIN_GITHUB_IDS: "1", CMS_GITHUB_CLIENT_ID: "a", CMS_GITHUB_CLIENT_SECRET: "b" })).toThrow("HTTPS");
    expect(loadConfig({ ...base, CMS_PUBLIC_URL: "https://cms.behu.sh/x", CMS_ADMIN_GITHUB_IDS: "1, 2", CMS_GITHUB_CLIENT_ID: "a", CMS_GITHUB_CLIENT_SECRET: "b" }).admin)
      .toMatchObject({ publicUrl: "https://cms.behu.sh", allowedGithubIds: new Set([1, 2]) });
  });
});
