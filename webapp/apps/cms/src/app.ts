// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { OpenAPIHono } from "@hono/zod-openapi";
import { serveStatic } from "hono/bun";
import { csrf } from "hono/csrf";
import { HTTPException } from "hono/http-exception";
import { secureHeaders } from "hono/secure-headers";
import type { AdminConfig } from "./config";
import type { Cms } from "./media/service";
import { PostError } from "./posts/service";
import { authRoutes } from "./routes/auth";
import { deviceRoutes } from "./routes/device";
import { healthRoutes } from "./routes/health";
import { meRoutes } from "./routes/me";
import { validationHook } from "./routes/errors";
import { postRoutes } from "./routes/posts";
import { siteRoutes } from "./routes/site";
import { tokenRoutes } from "./routes/tokens";

export type AppOptions = {
  isDraining?: () => boolean;
  /** GitHub sign-in for the admin; without it only bearer tokens work. */
  admin?: AdminConfig;
  /** The built admin (apps/cms-admin/dist), served on this origin. */
  adminDir?: string;
};

/** Paths the admin app never owns; everything else falls back to its index.html. */
const apiPaths = /^\/(v1|auth|health|openapi\.json|blog\/media|robots\.txt)(\/|$)/;

export function createApp(cms: Cms, options: AppOptions = {}) {
  const app = new OpenAPIHono({ defaultHook: validationHook });
  app.use("*", secureHeaders({
    // The admin loads only its own scripts. Styles may be inline (Radix positions
    // popovers with style attributes; the preview frame inlines article.css).
    // The preview is a srcdoc frame on this origin without scripts, which inherits this policy.
    contentSecurityPolicy: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'"],
      imgSrc: ["'self'", "data:", "blob:"],
      connectSrc: ["'self'"],
      fontSrc: ["'self'"],
      frameSrc: ["'self'"],
      objectSrc: ["'none'"],
      baseUri: ["'none'"],
      formAction: ["'self'", "https://github.com"],
      frameAncestors: ["'none'"],
    },
  }));
  // The admin API is never indexed, wherever it is hosted.
  app.use("*", async (context, next) => { await next(); context.header("x-robots-tag", "noindex, nofollow"); });
  // Cookie sessions: unsafe cross-site requests are refused by their Origin. A
  // request with a bearer token is not authenticated by cookie (auth/tokens.ts
  // reads the token first), and another site cannot send one without a CORS
  // preflight, which the CMS never allows; so, as in Django REST Framework, the
  // check applies to cookie requests only. CLIs send no Origin.
  if (options.admin) {
    const checkOrigin = csrf({ origin: options.admin.publicUrl });
    app.use("*", (context, next) => /^Bearer \S/.test(context.req.header("authorization") ?? "") ? next() : checkOrigin(context, next));
  }
  app.onError((error, context) => {
    if (error instanceof PostError) {
      return context.json({ error: { code: error.code, message: error.message, problems: error.problems.length ? error.problems : undefined } }, error.status);
    }
    // Hono's own refusals (the CSRF check) keep their status.
    if (error instanceof HTTPException) return error.getResponse();
    console.error(JSON.stringify({ level: "error", message: error.message }));
    return context.json({ error: { code: "internal", message: "Something went wrong." } }, 500);
  });
  app.get("/robots.txt", (context) => context.text("User-agent: *\nDisallow: /\n"));
  app.route("/", healthRoutes(cms.db, options.isDraining ?? (() => false)));
  if (options.admin) app.route("/", authRoutes(cms.db, options.admin));
  app.route("/", meRoutes(cms.db));
  app.route("/", deviceRoutes(cms.db, options.admin?.publicUrl));
  app.route("/", tokenRoutes(cms.db));
  app.route("/", postRoutes(cms));
  app.route("/", siteRoutes(cms));
  app.openAPIRegistry.registerComponent("securitySchemes", "bearer", { type: "http", scheme: "bearer" });
  app.doc31("/openapi.json", { openapi: "3.1.0", info: { title: "hush CMS", version: "1.0.0" } });
  if (options.adminDir) {
    const root = options.adminDir;
    const adminPath = (path: string) => !apiPaths.test(path);
    // Files through serveStatic (it refuses paths outside root); hashed assets are immutable.
    app.use("*", async (context, next) => adminPath(context.req.path) ? serveStatic({
      root,
      onFound: (path, found) => { found.header("cache-control", path.includes("/assets/") ? "public, max-age=31536000, immutable" : "no-cache"); },
    })(context, next) : next());
    // Any other admin address is a client-side route: answer with the app.
    app.get("*", async (context, next) => {
      if (!adminPath(context.req.path)) return next();
      context.header("cache-control", "no-cache");
      return context.html(await Bun.file(`${root}/index.html`).text());
    });
  }
  return app;
}
