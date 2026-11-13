// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The post lifecycle. Each change runs in one transaction with its revision, so
// a post, its keywords, its rendition and its history always agree. A scheduled
// or published post always passed the article contract and has a rendition, so
// anything live is valid.
import { and, asc, desc, eq, inArray, lte, sql } from "drizzle-orm";
import type { Database } from "../db/client";
import { postRenditions, postRevisions, postSecondaryKeywords, posts } from "../db/schema";
import { writeRenditions, type Cms } from "../media/service";
import { checkPost } from "./contract";
import { PostError } from "./errors";
import { postFields, type PostFields, type PostPatch } from "./fields";

type Transaction = Parameters<Parameters<Database["transaction"]>[0]>[0];
type Executor = Database | Transaction;

export type PostStatus = (typeof posts.$inferSelect)["status"];
export type Rendition = Omit<typeof postRenditions.$inferSelect, "postId">;
export type Post = typeof posts.$inferSelect & { secondaryKeywords: string[]; rendition: Rendition | null };

export { PostError };

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

function uniqueSlug(error: unknown) {
  const code = (error as { cause?: { code?: string } }).cause?.code ?? (error as { code?: string }).code;
  return code === "23505" ? new PostError(409, "slug_taken", "Another post in this language already uses this slug.") : error;
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
}) {
  try {
    return await db.transaction(async (tx) => {
      const { secondaryKeywords, ...columns } = change.fields ?? { secondaryKeywords: undefined };
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
      const post = await load(tx, id);
      await tx.insert(postRevisions).values({ postId: id, status: post.status, snapshot: editableFields(post), actor });
      return post;
    });
  } catch (error) {
    throw uniqueSlug(error);
  }
}

/** Validates and renders for going live; throws with the contract's problems. */
async function render(cms: Cms, id: string, fields: PostFields, publishedAt: Date, updatedAt: Date) {
  const { post, problems } = await checkPost(cms, id, fields, publishedAt, updatedAt);
  if (!post || problems.length) throw new PostError(422, "contract_failed", "The post does not meet the article contract.", problems);
  await writeRenditions(cms, post.images);
  return { heading: post.heading, html: post.html, toc: post.toc, readingMinutes: post.readingMinutes };
}

export async function listPosts(db: Database, filter: { lang?: string; status?: PostStatus }) {
  const rows: Loaded[] = await db.query.posts.findMany({
    where: and(filter.lang ? eq(posts.lang, filter.lang) : undefined, filter.status ? eq(posts.status, filter.status) : undefined),
    with: withRelations,
    orderBy: [desc(posts.updatedAt)],
  });
  return rows.map(compose);
}

export const getPost = load;

export function createDraft(db: Database, fields: PostFields, actor: string) {
  return write(db, actor, { fields });
}

export async function updatePost(cms: Cms, id: string, patch: PostPatch, actor: string) {
  const post = await load(cms.db, id);
  const fields = postFields.parse({ ...editableFields(post), ...patch });
  const updatedAt = new Date();
  // A live post changes only to another valid version.
  const rendition = post.status === "draft" ? undefined : await render(cms, id, fields, post.publishedAt!, updatedAt);
  return write(cms.db, actor, { id, fields, row: { updatedAt }, rendition });
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
 */
export async function publishPost(cms: Cms, id: string, actor: string, dates?: { publishedAt: Date; updatedAt: Date }) {
  const post = await load(cms.db, id);
  if (post.status === "published") return post;
  const publishedAt = dates?.publishedAt
    ?? (post.publishedAt && post.publishedAt.getTime() <= Date.now() ? post.publishedAt : new Date());
  const updatedAt = dates?.updatedAt ?? post.updatedAt;
  const rendition = await render(cms, id, editableFields(post), publishedAt, updatedAt);
  return write(cms.db, actor, { id, row: { status: "published", publishedAt, updatedAt }, rendition });
}

export async function unpublishPost(db: Database, id: string, actor: string) {
  const post = await load(db, id);
  if (post.status === "draft") return post;
  const keepDate = post.publishedAt && post.publishedAt.getTime() <= Date.now();
  return write(db, actor, { id, row: { status: "draft", publishedAt: keepDate ? post.publishedAt : null }, rendition: null });
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
    return published;
  });
}
