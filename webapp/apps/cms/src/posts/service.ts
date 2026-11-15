// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The post lifecycle. Each change runs in one transaction with its revision, so
// a post, its keywords, its rendition and its history always agree. A draft
// may be incomplete; a scheduled or published post always passed the article
// contract and has a rendition, so anything live is valid. A change to what the website shows also records the
// changed pages under the next site revision, in the same transaction.
import { blogPath, type BlogLanguage } from "@hush/article/taxonomy";
import { and, asc, desc, eq, inArray, like, lte, or, sql } from "drizzle-orm";
import type { Database } from "../db/client";
import { postRenditions, postRevisions, postSecondaryKeywords, posts, siteChanges, siteState } from "../db/schema";
import { writeRenditions, type Cms } from "../media/service";
import { checkPost, type CoPublished } from "./contract";
import { PostError } from "./errors";
import { draftDefaults, postFields, type PostFields, type PostPatch } from "./fields";
import { freeSlug, isUntitled, suggestedSlug, untitledSlug } from "./slug";

type Transaction = Parameters<Parameters<Database["transaction"]>[0]>[0];
export type Executor = Database | Transaction;

export type PostStatus = (typeof posts.$inferSelect)["status"];
export type Rendition = Omit<typeof postRenditions.$inferSelect, "postId">;
export type Post = typeof posts.$inferSelect & { secondaryKeywords: string[]; rendition: Rendition | null };

export { PostError };

/** The public address of a post (its language is validated on every write). */
const pagePath = (post: Post) => blogPath(post.lang as BlogLanguage, post.slug);

const withRelations = {
  secondaryKeywords: { columns: { keyword: true as const }, orderBy: [asc(postSecondaryKeywords.position)] },
  rendition: { columns: { heading: true as const, html: true as const, toc: true as const, readingMinutes: true as const, renderedAt: true as const } },
};

type Loaded = typeof posts.$inferSelect & { secondaryKeywords: Array<{ keyword: string }>; rendition: Rendition | null };

const compose = ({ secondaryKeywords, ...post }: Loaded): Post => ({
  ...post, secondaryKeywords: secondaryKeywords.map((row) => row.keyword),
});

async function load(db: Executor, id: string) {
  const post: Loaded | undefined = await db.query.posts.findFirst({ where: eq(posts.id, id), with: withRelations });
  if (!post) throw new PostError(404, "not_found", "No post with this id.");
  return compose(post);
}

/** The fields an author or agent writes, as stored in revisions. */
export function editableFields(post: Post): PostFields {
  return postFields.parse({
    lang: post.lang, slug: post.slug, title: post.title, description: post.description,
    keyword: post.keyword, secondaryKeywords: post.secondaryKeywords, type: post.type,
    cluster: post.cluster, author: post.author, imageAlt: post.imageAlt, markdown: post.markdown,
  });
}

/** How long one run of autosaves stays a single revision. */
const autosaveRunMs = 10 * 60_000;

function uniqueSlug(error: unknown) {
  const code = (error as { cause?: { code?: string } }).cause?.code ?? (error as { code?: string }).code;
  return code === "23505" ? new PostError(409, "slug_taken", "Another post in this language already uses this slug.") : error;
}

/** Takes the next site revision for changed articles and the blog index listing them. */
async function recordSiteChange(tx: Transaction, articlePaths: string[]) {
  const paths = new Set(articlePaths.flatMap((path) => [path, path.slice(0, path.lastIndexOf("/"))]));
  const [state] = await tx.update(siteState).set({ revision: sql`${siteState.revision} + 1` }).returning({ revision: siteState.revision });
  await tx.insert(siteChanges).values([...paths].map((path) => ({ revision: state!.revision, path })));
}

/**
 * Writes a post's state in one transaction: its row, its keywords, its
 * rendition (set, removed or left alone) and a revision.
 */
async function write(db: Database, actor: string, change: {
  id?: string;
  fields?: PostFields;
  row?: Partial<typeof posts.$inferInsert>;
  rendition?: Omit<Rendition, "renderedAt"> | null;
  /** Public pages this change alters. */
  sitePaths?: string[];
  /** The editor saving while its author writes: one revision per run, not one per save. */
  autosave?: boolean;
  /** Names the post after this slug, numbered when its language already has it (posts/slug.ts). */
  slugFrom?: string;
  /** Adjusts the fields to the slug they got. */
  named?: (fields: PostFields) => PostFields;
}) {
  try {
    return await db.transaction(async (tx) => {
      let fields = change.fields;
      if (fields && change.slugFrom) {
        // One writer at a time picks from the slugs of a language and base, so two posts
        // created or named at once never pick the same number. Held until this transaction ends.
        await tx.execute(sql`select pg_advisory_xact_lock(hashtext(${`post-slug\n${fields.lang}\n${change.slugFrom}`}))`);
        const taken = await tx.select({ slug: posts.slug }).from(posts)
          .where(and(eq(posts.lang, fields.lang), or(eq(posts.slug, change.slugFrom), like(posts.slug, `${change.slugFrom}-%`))));
        fields = { ...fields, slug: freeSlug(change.slugFrom, new Set(taken.map((row) => row.slug))) };
      }
      if (fields && change.named) fields = change.named(fields);
      const { secondaryKeywords, ...columns } = fields ?? { secondaryKeywords: undefined };
      const values = { ...columns, ...change.row };
      const [row] = change.id
        ? await tx.update(posts).set(values).where(eq(posts.id, change.id)).returning({ id: posts.id })
        : await tx.insert(posts).values(values as typeof posts.$inferInsert).returning({ id: posts.id });
      const id = row!.id;
      if (secondaryKeywords) {
        await tx.delete(postSecondaryKeywords).where(eq(postSecondaryKeywords.postId, id));
        if (secondaryKeywords.length) {
          await tx.insert(postSecondaryKeywords).values(secondaryKeywords.map((keyword, position) => ({ postId: id, position, keyword })));
        }
      }
      if (change.rendition === null) await tx.delete(postRenditions).where(eq(postRenditions.postId, id));
      else if (change.rendition) {
        const rendition = { ...change.rendition, renderedAt: new Date() };
        await tx.insert(postRenditions).values({ postId: id, ...rendition })
          .onConflictDoUpdate({ target: postRenditions.postId, set: rendition });
      }
      if (change.sitePaths?.length) await recordSiteChange(tx, change.sitePaths);
      const post = await load(tx, id);
      const snapshot = editableFields(post);
      if (change.autosave) {
        const [latest] = await tx.select().from(postRevisions).where(eq(postRevisions.postId, id))
          .orderBy(desc(postRevisions.createdAt), desc(postRevisions.id)).limit(1);
        if (latest?.autosave && latest.actor === actor && latest.status === post.status
          && Date.now() - latest.createdAt.getTime() < autosaveRunMs) {
          await tx.update(postRevisions).set({ snapshot }).where(eq(postRevisions.id, latest.id));
          return post;
        }
      }
      await tx.insert(postRevisions).values({ postId: id, status: post.status, snapshot, actor, autosave: Boolean(change.autosave) });
      return post;
    });
  } catch (error) {
    throw uniqueSlug(error);
  }
}

/** Validates and renders for going live; throws with the contract's problems. */
async function render(cms: Cms, id: string, fields: PostFields, publishedAt: Date, updatedAt: Date, coPublished: CoPublished = []) {
  const { post, problems } = await checkPost(cms, id, fields, publishedAt, updatedAt, coPublished);
  if (!post || problems.length) throw new PostError(422, "contract_failed", "The post does not meet the article contract.", problems);
  await writeRenditions(cms, post.images);
  return { heading: post.heading, html: post.html, toc: post.toc, readingMinutes: post.readingMinutes };
}

/**
 * Renders a post as it would go live, with unsaved changes, without writing
 * anything but its image renditions (content-addressed, so harmless).
 */
export async function previewPost(cms: Cms, id: string, patch: PostPatch) {
  const post = await load(cms.db, id);
  const fields = postFields.parse({ ...editableFields(post), ...patch });
  const now = new Date();
  const { post: rendered, problems } = await checkPost(cms, id, fields, post.publishedAt ?? now, now);
  if (rendered) await writeRenditions(cms, rendered.images);
  return {
    problems,
    rendition: rendered ? { heading: rendered.heading, html: rendered.html, toc: rendered.toc, readingMinutes: rendered.readingMinutes } : null,
  };
}

export async function listPosts(db: Executor, filter: { lang?: string; status?: PostStatus }) {
  const rows: Loaded[] = await db.query.posts.findMany({
    where: and(filter.lang ? eq(posts.lang, filter.lang) : undefined, filter.status ? eq(posts.status, filter.status) : undefined),
    with: withRelations,
    orderBy: [desc(posts.updatedAt)],
  });
  return rows.map(compose);
}

export const getPost = load;

/** A post's images are referenced as media/<slug>/<name>, so they follow a changed slug. */
const moveImages = (fields: PostFields, from: string): PostFields => (fields.slug === from ? fields
  : { ...fields, markdown: fields.markdown.replaceAll(`](media/${from}/`, `](media/${fields.slug}/`) });

/** Starts a draft from whatever is given; without a slug it takes one from its heading. */
export function createDraft(db: Database, input: PostPatch, actor: string) {
  const fields = postFields.parse({ ...draftDefaults, ...input, slug: input.slug ?? untitledSlug });
  return write(db, actor, { fields, slugFrom: input.slug ? undefined : suggestedSlug(fields) });
}

export async function updatePost(cms: Cms, id: string, patch: PostPatch, actor: string, options: { autosave?: boolean } = {}) {
  const post = await load(cms.db, id);
  const merged = postFields.parse({ ...editableFields(post), ...patch });
  // A draft that started without a heading takes its slug from the one it gets.
  const unnamed = post.status === "draft" && patch.slug === undefined && isUntitled(post.slug) && suggestedSlug(merged) !== untitledSlug;
  const fields = moveImages(merged, post.slug);
  const updatedAt = new Date();
  // A live post changes only to another valid version.
  const rendition = post.status === "draft" ? undefined : await render(cms, id, fields, post.publishedAt!, updatedAt);
  // A live post's page changes, at its old and its new address.
  const sitePaths = post.status === "published" ? [pagePath(post), blogPath(fields.lang, fields.slug)] : undefined;
  return write(cms.db, actor, {
    id, fields, row: { updatedAt }, rendition, sitePaths,
    // Only a draft is autosaved; every change to a live post is a revision of its own.
    autosave: options.autosave && post.status === "draft",
    ...(unnamed ? { slugFrom: suggestedSlug(merged), named: (named: PostFields) => moveImages(named, post.slug) } : {}),
  });
}

/** Removes a draft with its history and images. A live post is unpublished first, so nothing public disappears unannounced. */
export async function deletePost(db: Database, id: string) {
  const post = await load(db, id);
  if (post.status !== "draft") throw new PostError(409, "not_a_draft", "Unpublish the post before deleting it.");
  // Rows of the post go with it (cascade). Stored originals are named by their content and may be shared, so they stay.
  await db.delete(posts).where(and(eq(posts.id, id), eq(posts.status, "draft")));
}

export async function schedulePost(cms: Cms, id: string, at: Date, actor: string) {
  if (at.getTime() <= Date.now()) throw new PostError(422, "not_in_future", "Schedule a time in the future, or publish now.");
  const post = await load(cms.db, id);
  if (post.status === "published") throw new PostError(409, "already_published", "Unpublish the post before scheduling it.");
  const rendition = await render(cms, id, editableFields(post), at, at);
  return write(cms.db, actor, { id, row: { status: "scheduled", publishedAt: at }, rendition });
}

/**
 * @param dates an imported article's original publication and update dates;
 * otherwise a post published before keeps its date and a new one goes live now.
 * @param coPublished posts going live in the same import, which it may link to
 */
export async function publishPost(cms: Cms, id: string, actor: string, dates?: { publishedAt: Date; updatedAt: Date }, coPublished: CoPublished = []) {
  const post = await load(cms.db, id);
  if (post.status === "published") return post;
  const publishedAt = dates?.publishedAt
    ?? (post.publishedAt && post.publishedAt.getTime() <= Date.now() ? post.publishedAt : new Date());
  const updatedAt = dates?.updatedAt ?? post.updatedAt;
  const rendition = await render(cms, id, editableFields(post), publishedAt, updatedAt, coPublished);
  return write(cms.db, actor, { id, row: { status: "published", publishedAt, updatedAt }, rendition, sitePaths: [pagePath(post)] });
}

export async function unpublishPost(db: Database, id: string, actor: string) {
  const post = await load(db, id);
  if (post.status === "draft") return post;
  const keepDate = post.publishedAt && post.publishedAt.getTime() <= Date.now();
  const sitePaths = post.status === "published" ? [pagePath(post)] : undefined;
  return write(db, actor, { id, row: { status: "draft", publishedAt: keepDate ? post.publishedAt : null }, rendition: null, sitePaths });
}

export async function listRevisions(db: Database, id: string) {
  await load(db, id);
  return db.select().from(postRevisions).where(eq(postRevisions.postId, id)).orderBy(desc(postRevisions.createdAt), desc(postRevisions.id));
}

export async function restoreRevision(cms: Cms, id: string, revisionId: string, actor: string) {
  const [revision] = await cms.db.select().from(postRevisions).where(and(eq(postRevisions.id, revisionId), eq(postRevisions.postId, id)));
  if (!revision) throw new PostError(404, "not_found", "No revision with this id for this post.");
  return updatePost(cms, id, postFields.parse(revision.snapshot), actor);
}

/**
 * Publishes every scheduled post that is due, in one statement on the
 * database clock, so concurrent or repeated runs never publish twice.
 */
export async function publishDuePosts(db: Database) {
  return db.transaction(async (tx) => {
    const due = await tx.update(posts).set({ status: "published" })
      .where(and(eq(posts.status, "scheduled"), lte(posts.publishedAt, sql`now()`)))
      .returning({ id: posts.id });
    if (!due.length) return [];
    const rows: Loaded[] = await tx.query.posts.findMany({ where: inArray(posts.id, due.map((row) => row.id)), with: withRelations });
    const published = rows.map(compose);
    await tx.insert(postRevisions).values(published.map((post) => ({ postId: post.id, status: post.status, snapshot: editableFields(post), actor: "scheduler" })));
    await recordSiteChange(tx, published.map(pagePath));
    return published;
  });
}
