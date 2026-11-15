// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The device sign-in of the CLI (auth/device.ts). Starting and polling need no
// credentials, as RFC 8628 has it; deciding needs the signed-in owner. Bodies
// are JSON, so the admin's CSRF check (form posts only) never applies.
import { OpenAPIHono, createRoute, z } from "@hono/zod-openapi";
import {
  decideDeviceAuthorization, deviceCodeSeconds, pendingDeviceAuthorization, pollDeviceAuthorization, pollSeconds, startDeviceAuthorization,
} from "../auth/device";
import { requireOwner, tokenScopes, type AuthVariables } from "../auth/tokens";
import type { Database } from "../db/client";
import { errorSchema, validationHook } from "./errors";

const json = <T extends z.ZodType>(schema: T, description: string) => ({ description, content: { "application/json": { schema } } });
const userCodeParam = z.object({ userCode: z.string().describe("The code the CLI shows, such as BCDF-GHJK") });
const security = [{ bearer: [] }];

const pollMessages = {
  authorization_pending: "Waiting for the owner to authorize this sign-in.",
  slow_down: "Polled too soon; wait longer between polls.",
  access_denied: "The owner denied this sign-in.",
  expired_token: "The sign-in expired; start it again.",
  invalid_grant: "Unknown or already used device code.",
} as const;

export function deviceRoutes(db: Database, publicUrl?: string) {
  const app = new OpenAPIHono<{ Variables: AuthVariables }>({ defaultHook: validationHook });
  // Tokens and codes are never cached (RFC 6749, section 5.1).
  app.use("/v1/auth/device/*", async (context, next) => { await next(); context.header("cache-control", "no-store"); });
  app.use("/v1/auth/device", async (context, next) => { await next(); context.header("cache-control", "no-store"); });
  // A user code is eight letters with an optional dash, so the poll at /v1/auth/device/token never matches.
  const userCode = ":userCode{[A-Za-z]{4}-?[A-Za-z]{4}}";
  app.use(`/v1/auth/device/${userCode}`, requireOwner(db));
  app.use(`/v1/auth/device/${userCode}/:decision`, requireOwner(db));

  app.openapi(createRoute({
    method: "post", path: "/v1/auth/device", operationId: "startDeviceSignIn", tags: ["Access"],
    description: "Starts a device sign-in (RFC 8628): show userCode and verificationUriComplete to the person, then poll with deviceCode.",
    request: { body: { required: true, content: { "application/json": { schema: z.object({
      clientName: z.string().trim().min(1).max(80).describe("Names the token, such as \"hush-cms on Clemens's MacBook\""),
    }) } } } },
    responses: {
      200: json(z.object({
        deviceCode: z.string(), userCode: z.string(), verificationUri: z.url(), verificationUriComplete: z.url(),
        expiresIn: z.number().int().describe("Seconds until the codes expire"), interval: z.number().int().describe("Seconds to wait between polls"),
      }).openapi("DeviceSignIn"), "The codes"),
    },
  }), async (context) => {
    const { deviceCode, userCode } = await startDeviceAuthorization(db, context.req.valid("json").clientName);
    const verificationUri = `${publicUrl ?? new URL(context.req.url).origin}/device`;
    return context.json({
      deviceCode, userCode, verificationUri, verificationUriComplete: `${verificationUri}?code=${userCode}`,
      expiresIn: deviceCodeSeconds, interval: pollSeconds,
    }, 200);
  });

  app.openapi(createRoute({
    method: "post", path: "/v1/auth/device/token", operationId: "pollDeviceSignIn", tags: ["Access"],
    description: "One poll. Until the owner decides it answers 400 authorization_pending (slow_down when polled too soon); after an approval it answers the token, once.",
    request: { body: { required: true, content: { "application/json": { schema: z.object({ deviceCode: z.string().min(1) }) } } } },
    responses: {
      200: json(z.object({ token: z.string(), actor: z.string(), expiresAt: z.iso.datetime() }).openapi("DeviceToken"), "The new token, shown once"),
      400: json(errorSchema, "authorization_pending, slow_down, access_denied, expired_token or invalid_grant"),
    },
  }), async (context) => {
    const result = await pollDeviceAuthorization(db, context.req.valid("json").deviceCode);
    if ("error" in result) return context.json({ error: { code: result.error, message: pollMessages[result.error] } }, 400);
    return context.json({ token: result.token, actor: result.actor, expiresAt: result.expiresAt.toISOString() }, 200);
  });

  app.openapi(createRoute({
    method: "get", path: "/v1/auth/device/{userCode}", operationId: "getDeviceSignIn", tags: ["Access"], security,
    description: "A sign-in waiting for the owner's decision. The owner only.",
    request: { params: userCodeParam },
    responses: {
      200: json(z.object({
        userCode: z.string(), clientName: z.string(), expiresAt: z.iso.datetime(),
        scopes: z.array(z.enum(tokenScopes)), tokenDays: z.number().int().describe("How long the token will work"),
      }).openapi("PendingDeviceSignIn"), "The sign-in to decide"),
      401: json(errorSchema, "Not signed in"), 403: json(errorSchema, "Not the owner"),
      404: json(errorSchema, "No such code waiting: mistyped, expired or already decided"),
    },
  }), async (context) => {
    const pending = await pendingDeviceAuthorization(db, context.req.valid("param").userCode);
    if (!pending) return context.json({ error: { code: "not_found", message: "No sign-in is waiting for this code. It may be mistyped, expired or already decided." } }, 404);
    return context.json({ ...pending, scopes: [...pending.scopes], expiresAt: pending.expiresAt.toISOString() }, 200);
  });

  app.openapi(createRoute({
    method: "post", path: "/v1/auth/device/{userCode}/{decision}", operationId: "decideDeviceSignIn", tags: ["Access"], security,
    description: "The owner approves or denies a sign-in. The owner only.",
    request: { params: userCodeParam.extend({ decision: z.enum(["approve", "deny"]) }) },
    responses: {
      204: { description: "Decided" },
      401: json(errorSchema, "Not signed in"), 403: json(errorSchema, "Not the owner"),
      404: json(errorSchema, "No such code waiting: mistyped, expired or already decided"),
    },
  }), async (context) => {
    const { userCode, decision } = context.req.valid("param");
    if (!await decideDeviceAuthorization(db, userCode, decision, context.var.actor)) {
      return context.json({ error: { code: "not_found", message: "No sign-in is waiting for this code. It may be mistyped, expired or already decided." } }, 404);
    }
    return context.body(null, 204);
  });

  return app;
}
