// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Admin sign-in with a GitHub OAuth App (Arctic for the OAuth 2.0 exchange).
// No scope is requested: /user returns the id and login without one. Only
// GitHub user ids on the allowlist get a session; the GitHub access token is
// used once and not kept.
import { GitHub, generateState } from "arctic";
import { Hono, type Context } from "hono";
import { deleteCookie, getCookie, setCookie } from "hono/cookie";
import { createSession, endSession, sessionUser, setSessionCookie } from "../auth/sessions";
import type { AdminConfig } from "../config";
import type { Database } from "../db/client";

const stateCookie = "__Host-cms_oauth_state";
const githubUserUrl = "https://api.github.com/user";

type GitHubUser = { id: number; login: string };

const signInFailed = (context: Context, message: string, status: 400 | 403 = 400) =>
  context.html(`<!doctype html><meta charset="utf-8"><title>Sign-in failed</title><p>${message}</p><p><a href="/auth/github">Try again</a></p>`, status);

export function authRoutes(db: Database, admin: AdminConfig) {
  const github = new GitHub(admin.github.clientId, admin.github.clientSecret, `${admin.publicUrl}/auth/github/callback`);
  const app = new Hono();

  app.get("/auth/github", (context) => {
    const state = generateState();
    // Lax, not Strict: the callback is a top-level navigation from github.com.
    setCookie(context, stateCookie, state, { httpOnly: true, secure: true, sameSite: "Lax", path: "/", maxAge: 600 });
    return context.redirect(github.createAuthorizationURL(state, []).toString());
  });

  app.get("/auth/github/callback", async (context) => {
    const code = context.req.query("code");
    const state = context.req.query("state");
    const expected = getCookie(context, stateCookie);
    deleteCookie(context, stateCookie, { path: "/", secure: true });
    if (!code || !state || !expected || state !== expected) return signInFailed(context, "The sign-in expired or did not start here.");
    let user: GitHubUser;
    try {
      const tokens = await github.validateAuthorizationCode(code);
      const response = await fetch(githubUserUrl, {
        headers: { authorization: `Bearer ${tokens.accessToken()}`, accept: "application/vnd.github+json", "user-agent": "hush-cms" },
        signal: AbortSignal.timeout(10_000),
      });
      if (!response.ok) throw new Error(`GitHub answered ${response.status}`);
      user = await response.json() as GitHubUser;
    } catch (error) {
      console.error(JSON.stringify({ level: "error", message: "GitHub sign-in failed", error: String(error) }));
      return signInFailed(context, "GitHub did not confirm the sign-in.");
    }
    if (!admin.allowedGithubIds.has(user.id)) {
      console.info(JSON.stringify({ level: "info", message: "Refused an admin sign-in", githubUserId: user.id }));
      return signInFailed(context, "This GitHub account may not use the hush CMS.", 403);
    }
    const session = await createSession(db, { githubUserId: user.id, githubLogin: user.login });
    setSessionCookie(context, session.token, session.expiresAt);
    return context.redirect("/");
  });

  app.get("/auth/session", async (context) => {
    context.header("cache-control", "no-store");
    const user = await sessionUser(db, context);
    return user ? context.json({ login: user.githubLogin }) : context.json({ error: { code: "unauthorized", message: "Not signed in." } }, 401);
  });

  app.post("/auth/sign-out", async (context) => {
    await endSession(db, context);
    return context.body(null, 204);
  });

  return app;
}
