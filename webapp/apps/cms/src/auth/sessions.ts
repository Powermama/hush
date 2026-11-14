// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Admin sessions after a GitHub sign-in: a random 256-bit token in a
// __Host- cookie (HttpOnly, Secure, SameSite=Lax, whole origin), stored only
// as a SHA-256 hash. Following OWASP's session guidance, a session ends after
// 12 hours without use and at the latest after a week, and signing out ends
// it on the server. Unsafe requests are protected by SameSite and Hono's
// Origin check (csrf()) in app.ts.
import { randomBytes } from "node:crypto";
import { and, eq, gt, isNull, or } from "drizzle-orm";
import type { Context } from "hono";
import { deleteCookie, getCookie, setCookie } from "hono/cookie";
import type { Database } from "../db/client";
import { adminSessions } from "../db/schema";
import { hashToken } from "./hash";

export const sessionCookie = "__Host-cms_session";
export const sessionDays = 7;
export const sessionIdleHours = 12;

export type AdminUser = { githubUserId: number; githubLogin: string };

export async function createSession(db: Database, user: AdminUser, now = new Date()) {
  const token = randomBytes(32).toString("base64url");
  const expiresAt = new Date(now.getTime() + sessionDays * 86_400_000);
  await db.insert(adminSessions).values({ tokenHash: hashToken(token), ...user, expiresAt });
  return { token, expiresAt };
}

export function setSessionCookie(context: Context, token: string, expiresAt: Date) {
  setCookie(context, sessionCookie, token, {
    httpOnly: true, secure: true, sameSite: "Lax", path: "/", expires: expiresAt,
  });
}

/** The signed-in admin of this request, or undefined. */
export async function sessionUser(db: Database, context: Context, now = new Date()): Promise<AdminUser | undefined> {
  const token = getCookie(context, sessionCookie);
  if (!token) return undefined;
  const idleSince = new Date(now.getTime() - sessionIdleHours * 3_600_000);
  const [row] = await db.select().from(adminSessions).where(and(
    eq(adminSessions.tokenHash, hashToken(token)),
    gt(adminSessions.expiresAt, now),
    // A new session has not been seen yet; its creation counts as the last use.
    or(gt(adminSessions.lastSeenAt, idleSince), and(isNull(adminSessions.lastSeenAt), gt(adminSessions.createdAt, idleSince))),
  ));
  if (!row) return undefined;
  await db.update(adminSessions).set({ lastSeenAt: now }).where(eq(adminSessions.id, row.id));
  return { githubUserId: row.githubUserId, githubLogin: row.githubLogin };
}

export async function endSession(db: Database, context: Context) {
  const token = getCookie(context, sessionCookie);
  if (token) await db.delete(adminSessions).where(eq(adminSessions.tokenHash, hashToken(token)));
  deleteCookie(context, sessionCookie, { path: "/", secure: true });
  context.header("clear-site-data", '"cache", "cookies", "storage"');
}
