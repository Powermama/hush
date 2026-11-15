// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { OpenAPIHono, createRoute, z } from "@hono/zod-openapi";
import type { Database } from "../db/client";
import { requireScope, tokenScopes, type AuthVariables } from "../auth/tokens";
import { errorSchema, validationHook } from "./errors";

const callerSchema = z.object({
  actor: z.string().describe("token:<name> for a token, github:<login> for the signed-in owner"),
  scopes: z.array(z.enum(tokenScopes)),
  expiresAt: z.iso.datetime().nullable().describe("When the token stops working; null for the owner and for tokens without an expiry."),
}).openapi("Caller");

/** Who the request comes from, so a client can show its token's name, scopes and expiry. */
export function meRoutes(db: Database) {
  const app = new OpenAPIHono<{ Variables: AuthVariables }>({ defaultHook: validationHook });
  app.use("/v1/me", requireScope(db));
  app.openapi(createRoute({
    method: "get", path: "/v1/me", operationId: "getCaller", tags: ["Access"], security: [{ bearer: [] }],
    responses: {
      200: { description: "The token or owner making the request", content: { "application/json": { schema: callerSchema } } },
      401: { description: "Missing or invalid token", content: { "application/json": { schema: errorSchema } } },
    },
  }), (context) => {
    const { actor, scopes, expiresAt } = context.var.caller;
    return context.json({ actor, scopes: [...scopes], expiresAt: expiresAt?.toISOString() ?? null }, 200);
  });
  return app;
}
