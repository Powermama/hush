// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { frontMatterFields } from "@hush/article";
import { z } from "@hono/zod-openapi";

/**
 * What an author or agent writes. Dates and status are not fields: the CMS
 * sets them through draft, schedule, publish and unpublish.
 */
export const postFields = frontMatterFields
  .omit({ published: true, updated: true, draft: true, schema: true })
  .extend({ markdown: z.string().min(1) });
export type PostFields = z.infer<typeof postFields>;

export const postPatch = postFields.partial();
export type PostPatch = z.infer<typeof postPatch>;
