// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { frontMatterFields } from "@hush/article";
import { blogAuthorIds } from "@hush/article/authors";
import { blogClusterIds } from "@hush/article/taxonomy";
import { z } from "@hono/zod-openapi";

/**
 * What an author or agent writes. Dates and status are not fields: the CMS
 * sets them through draft, schedule, publish and unpublish.
 *
 * A draft is work in progress, so its texts may be empty or of any length. The
 * article contract (@hush/article) applies when a post is scheduled or
 * published and to every change while it is live (posts/contract.ts).
 */
export const postFields = frontMatterFields.pick({ lang: true, slug: true, type: true, cluster: true, author: true }).extend({
  title: z.string(),
  description: z.string(),
  keyword: z.string(),
  secondaryKeywords: z.array(z.string().min(1)).max(8),
  imageAlt: z.string(),
  markdown: z.string(),
});
export type PostFields = z.infer<typeof postFields>;

export const postPatch = postFields.partial();
export type PostPatch = z.infer<typeof postPatch>;

/** What a new draft starts with where the request leaves a field out; its slug comes from its heading (posts/slug.ts). */
export const draftDefaults: Omit<PostFields, "slug"> = {
  lang: "en", type: "how-to", cluster: blogClusterIds[0], author: blogAuthorIds[0],
  title: "", description: "", keyword: "", secondaryKeywords: [], imageAlt: "", markdown: "",
};
