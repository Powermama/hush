// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Bearer tokens for agents and scripts: 256 random bits, shown once, stored as
// a SHA-256 hash, limited by scopes and an optional expiry.
import { randomBytes } from "node:crypto";
import { and, eq, gt, isNull, or } from "drizzle-orm";
import type { Context } from "hono";
import { createMiddleware } from "hono/factory";
import type { Database } from "../db/client";
import { hashToken } from "./hash";
import { sessionUser } from "./sessions";
import { apiTokenScopes, apiTokens } from "../db/schema";

export const tokenScopes = ["posts:read", "posts:write", "posts:publish"] as const;
export type TokenScope = (typeof tokenScopes)[number];

export { hashToken };

export async function createToken(db: Database, input: { name: string; scopes: TokenScope[]; expiresAt?: Date }) {
  const token = `hcms_${randomBytes(32).toString("base64url")}`;
  await db.transaction(async (tx) => {
    const [row] = await tx.insert(apiTokens).values({ name: input.name, expiresAt: input.expiresAt, tokenHash: hashToken(token) }).returning();
    await tx.insert(apiTokenScopes).values(input.scopes.map((scope) => ({ tokenId: row!.id, scope })));
  });
  return token;
}

/** Who sent a request: a token with its scopes and expiry, or the signed-in owner, who holds every scope. */
export type Caller = { actor: string; owner: boolean; scopes: readonly TokenScope[]; expiresAt: Date | null };

/**
 * Every token acts for an agent, the owner's own included: what readers see
 * changes through a token only with the owner's approval (posts/service.ts).
 * The owner acts through the admin.
 */
export const isAgent = (actor: string) => actor.startsWith("token:");

export type AuthVariables = { actor: string; caller: Caller };

const unauthorized = { code: "unauthorized", message: "Sign in or send a bearer token." };

/** The caller of a request, or why it has none. A token's use is recorded as its last use. */
async function authenticate(db: Database, context: Context): Promise<Caller | { code: string; message: string }> {
  const header = context.req.header("authorization") ?? "";
  const token = /^Bearer (\S+)$/.exec(header)?.[1];
  if (!token) {
    const admin = await sessionUser(db, context);
    return admin ? { actor: `github:${admin.githubLogin}`, owner: true, scopes: tokenScopes, expiresAt: null } : unauthorized;
  }
  const [row] = await db.select().from(apiTokens).where(and(
    eq(apiTokens.tokenHash, hashToken(token)),
    isNull(apiTokens.revokedAt),
    or(isNull(apiTokens.expiresAt), gt(apiTokens.expiresAt, new Date())),
  ));
  if (!row) return { code: "unauthorized", message: "The token is unknown, expired or revoked." };
  const granted = await db.select({ scope: apiTokenScopes.scope }).from(apiTokenScopes).where(eq(apiTokenScopes.tokenId, row.id));
  await db.update(apiTokens).set({ lastUsedAt: new Date() }).where(eq(apiTokens.id, row.id));
  return {
    actor: `token:${row.name}`,
    owner: false,
    scopes: tokenScopes.filter((scope) => granted.some((grant) => grant.scope === scope)),
    expiresAt: row.expiresAt,
  };
}

/**
 * Accepts a valid, unexpired, unrevoked bearer token that carries `scope`, or
 * the signed-in admin, who holds every scope. Without a scope, any caller.
 */
export function requireScope(db: Database, scope?: TokenScope) {
  return createMiddleware<{ Variables: AuthVariables }>(async (context, next) => {
    const caller = await authenticate(db, context);
    if (!("actor" in caller)) return context.json({ error: caller }, 401);
    if (scope && !caller.scopes.includes(scope)) {
      return context.json({ error: { code: "forbidden", message: `The token lacks the ${scope} scope.` } }, 403);
    }
    context.set("actor", caller.actor);
    context.set("caller", caller);
    await next();
  });
}

/** Only the signed-in owner: approvals are never a token's, whatever its scopes. */
export function requireOwner(db: Database) {
  return createMiddleware<{ Variables: AuthVariables }>(async (context, next) => {
    const caller = await authenticate(db, context);
    if (!("actor" in caller)) return context.json({ error: caller }, 401);
    if (!caller.owner) return context.json({ error: { code: "owner_only", message: "Only the owner does this, signed in to the admin." } }, 403);
    context.set("actor", caller.actor);
    context.set("caller", caller);
    await next();
  });
}
