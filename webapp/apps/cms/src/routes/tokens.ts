// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The tokens that work, for the admin's Integrations settings: the owner sees
// each one (never its secret) and can revoke it.
import { OpenAPIHono, createRoute, z } from "@hono/zod-openapi";
import { and, desc, eq, isNull } from "drizzle-orm";
import { requireOwner, revokeToken, tokenScopes, type AuthVariables } from "../auth/tokens";
import type { Database } from "../db/client";
import { apiTokenScopes, apiTokens, deviceAuthorizations } from "../db/schema";
import { errorSchema, validationHook } from "./errors";

const tokenSchema = z.object({
  id: z.uuid(),
  name: z.string(),
  kind: z.enum(["device", "service"]).describe("device: a CLI signed in through /device; service: made with cms:token, such as the website build's"),
  scopes: z.array(z.enum(tokenScopes)),
  createdAt: z.iso.datetime(),
  lastUsedAt: z.iso.datetime().nullable(),
  expiresAt: z.iso.datetime().nullable(),
}).openapi("Token");

const json = <T extends z.ZodType>(schema: T, description: string) => ({ description, content: { "application/json": { schema } } });
const security = [{ bearer: [] }];

export function tokenRoutes(db: Database) {
  const app = new OpenAPIHono<{ Variables: AuthVariables }>({ defaultHook: validationHook });
  app.use("/v1/tokens", requireOwner(db));
  app.use("/v1/tokens/:id", requireOwner(db));

  app.openapi(createRoute({
    method: "get", path: "/v1/tokens", operationId: "listTokens", tags: ["Access"], security,
    description: "Every token that is not revoked, newest first, without its secret. The owner only.",
    responses: { 200: json(z.object({ tokens: z.array(tokenSchema) }), "The tokens"), 401: json(errorSchema, "Not signed in"), 403: json(errorSchema, "Not the owner") },
  }), async (context) => {
    const rows = await db.select({
      id: apiTokens.id, name: apiTokens.name, createdAt: apiTokens.createdAt, lastUsedAt: apiTokens.lastUsedAt,
      expiresAt: apiTokens.expiresAt, device: deviceAuthorizations.id,
    }).from(apiTokens)
      .leftJoin(deviceAuthorizations, eq(deviceAuthorizations.tokenId, apiTokens.id))
      .where(isNull(apiTokens.revokedAt))
      .orderBy(desc(apiTokens.createdAt));
    const scopes = await db.select().from(apiTokenScopes);
    return context.json({
      tokens: rows.map((row) => ({
        id: row.id, name: row.name, kind: row.device ? "device" as const : "service" as const,
        scopes: tokenScopes.filter((scope) => scopes.some((grant) => grant.tokenId === row.id && grant.scope === scope)),
        createdAt: row.createdAt.toISOString(), lastUsedAt: row.lastUsedAt?.toISOString() ?? null, expiresAt: row.expiresAt?.toISOString() ?? null,
      })),
    }, 200);
  });

  app.openapi(createRoute({
    method: "delete", path: "/v1/tokens/{id}", operationId: "revokeToken", tags: ["Access"], security,
    description: "Revokes a token: requests with it get 401 from then on. The owner only.",
    request: { params: z.object({ id: z.uuid() }) },
    responses: {
      204: { description: "Revoked" }, 401: json(errorSchema, "Not signed in"), 403: json(errorSchema, "Not the owner"),
      404: json(errorSchema, "No such token, or already revoked"),
    },
  }), async (context) => {
    const { id } = context.req.valid("param");
    const [token] = await db.select({ id: apiTokens.id }).from(apiTokens).where(and(eq(apiTokens.id, id), isNull(apiTokens.revokedAt)));
    if (!token) return context.json({ error: { code: "not_found", message: "No such token, or it is already revoked." } }, 404);
    await revokeToken(db, id);
    return context.body(null, 204);
  });

  return app;
}
