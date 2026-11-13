// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Bearer tokens for agents and scripts: 256 random bits, shown once, stored as
// a SHA-256 hash, limited by scopes and an optional expiry.
import { createHash, randomBytes } from "node:crypto";
import { and, eq, gt, isNull, or } from "drizzle-orm";
import { createMiddleware } from "hono/factory";
import type { Database } from "../db/client";
import { apiTokenScopes, apiTokens } from "../db/schema";

export const tokenScopes = ["posts:read", "posts:write", "posts:publish"] as const;
export type TokenScope = (typeof tokenScopes)[number];

export const hashToken = (token: string) => createHash("sha256").update(token).digest("hex");

export async function createToken(db: Database, input: { name: string; scopes: TokenScope[]; expiresAt?: Date }) {
  const token = `hcms_${randomBytes(32).toString("base64url")}`;
  await db.transaction(async (tx) => {
    const [row] = await tx.insert(apiTokens).values({ name: input.name, expiresAt: input.expiresAt, tokenHash: hashToken(token) }).returning();
    await tx.insert(apiTokenScopes).values(input.scopes.map((scope) => ({ tokenId: row!.id, scope })));
  });
  return token;
}

export type AuthVariables = { actor: string };

/** Accepts a valid, unexpired, unrevoked token that carries `scope`. */
export function requireScope(db: Database, scope: TokenScope) {
  return createMiddleware<{ Variables: AuthVariables }>(async (context, next) => {
    const header = context.req.header("authorization") ?? "";
    const token = /^Bearer (\S+)$/.exec(header)?.[1];
    if (!token) return context.json({ error: { code: "unauthorized", message: "A bearer token is required." } }, 401);
    const [row] = await db.select().from(apiTokens).where(and(
      eq(apiTokens.tokenHash, hashToken(token)),
      isNull(apiTokens.revokedAt),
      or(isNull(apiTokens.expiresAt), gt(apiTokens.expiresAt, new Date())),
    ));
    if (!row) return context.json({ error: { code: "unauthorized", message: "The token is unknown, expired or revoked." } }, 401);
    const [granted] = await db.select().from(apiTokenScopes)
      .where(and(eq(apiTokenScopes.tokenId, row.id), eq(apiTokenScopes.scope, scope)));
    if (!granted) {
      return context.json({ error: { code: "forbidden", message: `The token lacks the ${scope} scope.` } }, 403);
    }
    await db.update(apiTokens).set({ lastUsedAt: new Date() }).where(eq(apiTokens.id, row.id));
    context.set("actor", `token:${row.name}`);
    await next();
  });
}
