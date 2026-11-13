// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Normalised to third normal form. Posts follow Ghost's lifecycle: draft,
// scheduled (published_at in the future) and published. A post row holds only
// what an author writes; the HTML rendered when it goes live is derived data
// and lives in post_renditions. Two JSON columns are deliberate: a revision's
// snapshot is an immutable historical record and a rendition's table of
// contents is a value of the rendered document; neither is queried inside.
// Authors and clusters are ids validated against @hush/article.
import type { TocEntry } from "@hush/article";
import { relations, sql } from "drizzle-orm";
import { bigint, check, index, integer, jsonb, pgEnum, pgTable, primaryKey, smallint, text, timestamp, uniqueIndex, uuid } from "drizzle-orm/pg-core";

export const postStatus = pgEnum("post_status", ["draft", "scheduled", "published"]);
export const tokenScope = pgEnum("token_scope", ["posts:read", "posts:write", "posts:publish"]);

export const posts = pgTable("posts", {
  id: uuid("id").primaryKey().defaultRandom(),
  lang: text("lang").notNull(),
  slug: text("slug").notNull(),
  status: postStatus("status").notNull().default("draft"),
  title: text("title").notNull(),
  description: text("description").notNull(),
  keyword: text("keyword").notNull(),
  type: text("type").notNull(),
  cluster: text("cluster").notNull(),
  author: text("author").notNull(),
  imageAlt: text("image_alt").notNull(),
  markdown: text("markdown").notNull(),
  publishedAt: timestamp("published_at", { withTimezone: true }),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
}, (table) => [
  uniqueIndex("posts_lang_slug").on(table.lang, table.slug),
  index("posts_status_published_at").on(table.status, table.publishedAt),
]);

export const postSecondaryKeywords = pgTable("post_secondary_keywords", {
  postId: uuid("post_id").notNull().references(() => posts.id, { onDelete: "cascade" }),
  position: smallint("position").notNull(),
  keyword: text("keyword").notNull(),
}, (table) => [primaryKey({ columns: [table.postId, table.position] })]);

/**
 * Images a post's Markdown references as media/<slug>/<name>. The original is
 * stored once under originals/<sha256>; its WebP renditions are written when the
 * post goes live.
 */
export const media = pgTable("media", {
  id: uuid("id").primaryKey().defaultRandom(),
  postId: uuid("post_id").notNull().references(() => posts.id, { onDelete: "cascade" }),
  name: text("name").notNull(),
  contentType: text("content_type").notNull(),
  sha256: text("sha256").notNull(),
  sizeBytes: integer("size_bytes").notNull(),
  width: integer("width").notNull(),
  height: integer("height").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
}, (table) => [uniqueIndex("media_post_name").on(table.postId, table.name)]);

/** What a scheduled or published post renders to, after passing the article contract. */
export const postRenditions = pgTable("post_renditions", {
  postId: uuid("post_id").primaryKey().references(() => posts.id, { onDelete: "cascade" }),
  heading: text("heading").notNull(),
  html: text("html").notNull(),
  toc: jsonb("toc").$type<TocEntry[]>().notNull(),
  readingMinutes: integer("reading_minutes").notNull(),
  renderedAt: timestamp("rendered_at", { withTimezone: true }).notNull().defaultNow(),
});

/** Every save and status change, so any earlier version can be restored. */
export const postRevisions = pgTable("post_revisions", {
  id: uuid("id").primaryKey().defaultRandom(),
  postId: uuid("post_id").notNull().references(() => posts.id, { onDelete: "cascade" }),
  status: postStatus("status").notNull(),
  snapshot: jsonb("snapshot").notNull(),
  actor: text("actor").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
}, (table) => [index("post_revisions_post_created").on(table.postId, table.createdAt)]);

/**
 * What the website shows, as a revision number. Every change to a public page
 * (publish, live edit, unpublish, a due post) takes the next revision in its
 * post's transaction; the export carries the revision it reflects and the
 * built site serves it back. One row; updating it serialises revisions in
 * commit order. The rest of the row is the deploy loop's own state.
 */
export const siteState = pgTable("site_state", {
  id: smallint("id").primaryKey().default(1),
  revision: bigint("revision", { mode: "number" }).notNull().default(0),
  /** Highest revision whose pages search engines were told about. */
  notifiedRevision: bigint("notified_revision", { mode: "number" }).notNull().default(0),
  /** The revision the last requested deploy is meant to make live, and when it was asked for. */
  deployRevision: bigint("deploy_revision", { mode: "number" }),
  deployRequestedAt: timestamp("deploy_requested_at", { withTimezone: true }),
}, (table) => [check("site_state_single_row", sql`${table.id} = 1`)]);

/** The public pages each site revision changed. */
export const siteChanges = pgTable("site_changes", {
  revision: bigint("revision", { mode: "number" }).notNull(),
  path: text("path").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
}, (table) => [primaryKey({ columns: [table.revision, table.path] })]);

/** Bearer tokens for agents and scripts. Only a SHA-256 hash is stored. */
export const apiTokens = pgTable("api_tokens", {
  id: uuid("id").primaryKey().defaultRandom(),
  name: text("name").notNull(),
  tokenHash: text("token_hash").notNull().unique(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  expiresAt: timestamp("expires_at", { withTimezone: true }),
  lastUsedAt: timestamp("last_used_at", { withTimezone: true }),
  revokedAt: timestamp("revoked_at", { withTimezone: true }),
});

export const apiTokenScopes = pgTable("api_token_scopes", {
  tokenId: uuid("token_id").notNull().references(() => apiTokens.id, { onDelete: "cascade" }),
  scope: tokenScope("scope").notNull(),
}, (table) => [primaryKey({ columns: [table.tokenId, table.scope] })]);

export const postRelations = relations(posts, ({ many, one }) => ({
  secondaryKeywords: many(postSecondaryKeywords),
  rendition: one(postRenditions, { fields: [posts.id], references: [postRenditions.postId] }),
}));
export const postSecondaryKeywordRelations = relations(postSecondaryKeywords, ({ one }) => ({
  post: one(posts, { fields: [postSecondaryKeywords.postId], references: [posts.id] }),
}));
