// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { z, type Hook } from "@hono/zod-openapi";

export const errorSchema = z.object({
  error: z.object({ code: z.string(), message: z.string(), problems: z.array(z.string()).optional() }),
}).openapi("Error");

/** Answers requests that do not match a route's schema with the API's error shape. */
export const validationHook: Hook<any, any, any, any> = (result, context) => {
  if (!result.success) {
    return context.json({ error: {
      code: "invalid_request", message: "The request does not match the API.",
      problems: result.error.issues.map((issue) => `${issue.path.join(".") || "(root)"}: ${issue.message}`),
    } }, 400);
  }
};
