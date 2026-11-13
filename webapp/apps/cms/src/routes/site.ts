// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// What the website build reads: the export of published posts and the image
// originals it lists. Both need posts:read; the build holds a read-only token.
import { OpenAPIHono, createRoute, z } from "@hono/zod-openapi";
import { eq } from "drizzle-orm";
import { requireScope, type AuthVariables } from "../auth/tokens";
import { media } from "../db/schema";
import { originalKey, type Cms } from "../media/service";
import { exportSite } from "../site/export";
import { errorSchema, validationHook } from "./errors";

const json = <T extends z.ZodType>(schema: T, description: string) => ({ description, content: { "application/json": { schema } } });
const security = [{ bearer: [] }];
const auth = {
  401: json(errorSchema, "Missing or invalid token"),
  403: json(errorSchema, "The token lacks the required scope"),
};

const exportSchema = z.object({
  revision: z.number().int().describe("The site revision these posts reflect; the built site serves it at /blog/revision.txt."),
  files: z.array(z.object({
    path: z.string().describe("<lang>/<slug>.md"),
    markdown: z.string().describe("The article in the hush-seo Markdown format."),
    media: z.array(z.object({
      path: z.string().describe("<lang>/media/<slug>/<name>"),
      sha256: z.string(),
      contentType: z.string(),
    })),
  })),
}).openapi("SiteExport");

export function siteRoutes(cms: Cms) {
  const app = new OpenAPIHono<{ Variables: AuthVariables }>({ defaultHook: validationHook });
  app.use("/v1/site/export", requireScope(cms.db, "posts:read"));
  app.use("/v1/media/:sha256", requireScope(cms.db, "posts:read"));

  app.openapi(createRoute({
    method: "get", path: "/v1/site/export", operationId: "exportSite", tags: ["Site"], security,
    description: "Every published post as a hush-seo Markdown file, with the images it references. The website build writes these files into a content directory.",
    responses: { 200: json(exportSchema, "The published posts"), ...auth },
  }), async (context) => context.json(await exportSite(cms.db), 200));

  app.openapi(createRoute({
    method: "get", path: "/v1/media/{sha256}", operationId: "getMediaOriginal", tags: ["Site"], security,
    request: { params: z.object({ sha256: z.string().regex(/^[0-9a-f]{64}$/) }) },
    responses: {
      200: { description: "The original image as uploaded", content: { "image/png": { schema: z.string().openapi({ type: "string", format: "binary" }) } } },
      ...auth,
      404: json(errorSchema, "No image with this hash"),
    },
  }), async (context) => {
    const { sha256 } = context.req.valid("param");
    const [row] = await cms.db.select({ contentType: media.contentType }).from(media).where(eq(media.sha256, sha256)).limit(1);
    const bytes = row && await cms.media.get(originalKey(sha256));
    if (!row || !bytes) return context.json({ error: { code: "not_found", message: "No image with this hash." } }, 404);
    return context.body(bytes as Uint8Array<ArrayBuffer>, 200, { "content-type": row.contentType, "cache-control": "private, max-age=31536000, immutable" });
  });

  return app;
}
