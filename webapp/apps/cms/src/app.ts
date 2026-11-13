// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { OpenAPIHono } from "@hono/zod-openapi";
import { secureHeaders } from "hono/secure-headers";
import type { Cms } from "./media/service";
import { PostError } from "./posts/service";
import { healthRoutes } from "./routes/health";
import { validationHook } from "./routes/errors";
import { postRoutes } from "./routes/posts";
import { siteRoutes } from "./routes/site";

export function createApp(cms: Cms, options: { isDraining?: () => boolean } = {}) {
  const app = new OpenAPIHono({ defaultHook: validationHook });
  app.use("*", secureHeaders());
  // The admin API is never indexed, wherever it is hosted.
  app.use("*", async (context, next) => { await next(); context.header("x-robots-tag", "noindex, nofollow"); });
  app.onError((error, context) => {
    if (error instanceof PostError) {
      return context.json({ error: { code: error.code, message: error.message, problems: error.problems.length ? error.problems : undefined } }, error.status);
    }
    console.error(JSON.stringify({ level: "error", message: error.message }));
    return context.json({ error: { code: "internal", message: "Something went wrong." } }, 500);
  });
  app.route("/", healthRoutes(cms.db, options.isDraining ?? (() => false)));
  app.route("/", postRoutes(cms));
  app.route("/", siteRoutes(cms));
  app.openAPIRegistry.registerComponent("securitySchemes", "bearer", { type: "http", scheme: "bearer" });
  app.doc31("/openapi.json", { openapi: "3.1.0", info: { title: "hush CMS", version: "1.0.0" } });
  return app;
}
