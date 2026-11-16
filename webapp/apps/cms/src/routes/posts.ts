// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { OpenAPIHono, createRoute, z } from "@hono/zod-openapi";
import { requireOwner, requireScope, type AuthVariables } from "../auth/tokens";
import { errorSchema, validationHook } from "./errors";
import { bodyLimit } from "hono/body-limit";
import { listMedia, maxImageBytes, uploadMedia, type Cms } from "../media/service";
import { postFields, postPatch } from "../posts/fields";
import {
  approvePost, createDraft, deletePost, getPost, listPosts, listRevisions, previewPost, publishPost, restoreRevision, schedulePost, unpublishPost, updatePost,
  type Post,
} from "../posts/service";

const statusSchema = z.enum(["draft", "scheduled", "published"]);

const postSchema = postFields.extend({
  id: z.uuid(),
  status: statusSchema,
  publishedAt: z.iso.datetime().nullable(),
  createdAt: z.iso.datetime(),
  updatedAt: z.iso.datetime(),
  rendition: z.object({
    heading: z.string(),
    html: z.string(),
    toc: z.array(z.object({ id: z.string(), text: z.string() })),
    readingMinutes: z.number().int(),
    renderedAt: z.iso.datetime(),
  }).nullable().describe("What the post renders to; present while it is scheduled or published."),
  contentHash: z.string().describe("Names the post's fields and images as they are now; the owner approves a post by it."),
  approval: z.object({
    approvedBy: z.string(),
    approvedAt: z.iso.datetime(),
    current: z.boolean().describe("Whether it covers the post as it is now; any change to the text or an image leaves it lapsed."),
  }).nullable().describe("The owner's approval, which agents need to schedule or publish the post."),
}).openapi("Post");

const revisionSchema = z.object({
  id: z.uuid(), postId: z.uuid(), status: statusSchema, snapshot: postFields, actor: z.string(),
  autosave: z.boolean().describe("Written by the editor's autosave; holds the last state of that run."), createdAt: z.iso.datetime(),
}).openapi("Revision");

const serialize = (post: Post) => postSchema.parse({
  ...post,
  publishedAt: post.publishedAt?.toISOString() ?? null,
  createdAt: post.createdAt.toISOString(),
  updatedAt: post.updatedAt.toISOString(),
  rendition: post.rendition && { ...post.rendition, renderedAt: post.rendition.renderedAt.toISOString() },
  approval: post.approval && { ...post.approval, approvedAt: post.approval.approvedAt.toISOString() },
});

const json = <T extends z.ZodType>(schema: T, description: string) => ({ description, content: { "application/json": { schema } } });
const errors = {
  401: json(errorSchema, "Missing or invalid token"),
  403: json(errorSchema, "The token lacks the required scope, or the change needs the owner"),
  404: json(errorSchema, "No such post"),
  409: json(errorSchema, "Conflicts with the post's state or another post"),
  422: json(errorSchema, "The post does not meet the article contract"),
};
const idParam = z.object({ id: z.uuid() });
const security = [{ bearer: [] }];

export function postRoutes(cms: Cms) {
  const { db } = cms;
  const app = new OpenAPIHono<{ Variables: AuthVariables }>({ defaultHook: validationHook });

  app.use("/v1/posts", async (context, next) => requireScope(db, context.req.method === "GET" ? "posts:read" : "posts:write")(context, next));
  app.use("/v1/posts/:id", async (context, next) => requireScope(db, context.req.method === "GET" ? "posts:read" : "posts:write")(context, next));
  app.use("/v1/posts/:id/revisions", requireScope(db, "posts:read"));
  app.use("/v1/posts/:id/revisions/:revisionId/restore", requireScope(db, "posts:write"));
  for (const action of ["schedule", "publish", "unpublish"]) app.use(`/v1/posts/:id/${action}`, requireScope(db, "posts:publish"));
  app.use("/v1/posts/:id/preview", requireScope(db, "posts:write"));
  app.use("/v1/posts/:id/approve", requireOwner(db));

  app.openapi(createRoute({
    method: "get", path: "/v1/posts", operationId: "listPosts", tags: ["Posts"], security,
    request: { query: z.object({ lang: z.enum(["en", "de"]).optional(), status: statusSchema.optional() }) },
    responses: { 200: json(z.object({ posts: z.array(postSchema) }), "Posts, most recently changed first"), 401: errors[401], 403: errors[403] },
  }), async (context) => {
    const posts = await listPosts(db, context.req.valid("query"));
    return context.json({ posts: posts.map(serialize) }, 200);
  });

  app.openapi(createRoute({
    method: "post", path: "/v1/posts", operationId: "createDraft", tags: ["Posts"], security,
    description: "Starts a draft from any of the fields; it may be incomplete. Without a slug it takes one from its H1 (\"untitled\" until it has one). The article contract applies when the post is scheduled or published.",
    request: { body: { required: true, content: { "application/json": { schema: postPatch } } } },
    responses: { 201: json(postSchema, "The new draft"), 401: errors[401], 403: errors[403], 409: errors[409] },
  }), async (context) => context.json(serialize(await createDraft(db, context.req.valid("json"), context.var.actor)), 201));

  app.openapi(createRoute({
    method: "get", path: "/v1/posts/{id}", operationId: "getPost", tags: ["Posts"], security,
    request: { params: idParam },
    responses: { 200: json(postSchema, "The post"), 401: errors[401], 403: errors[403], 404: errors[404] },
  }), async (context) => context.json(serialize(await getPost(db, context.req.valid("param").id)), 200));

  app.openapi(createRoute({
    method: "patch", path: "/v1/posts/{id}", operationId: "updatePost", tags: ["Posts"], security,
    description: "Changes fields. A scheduled or published post is re-validated and re-rendered; an invalid change is refused. With autosave=true, the saves of one writing session (same author, up to ten minutes) share one revision. Tokens change drafts only (403 live_post).",
    request: { params: idParam, query: z.object({ autosave: z.enum(["true", "false"]).optional() }), body: { required: true, content: { "application/json": { schema: postPatch } } } },
    responses: { 200: json(postSchema, "The updated post"), ...errors },
  }), async (context) => context.json(serialize(await updatePost(
    cms, context.req.valid("param").id, context.req.valid("json"), context.var.actor, { autosave: context.req.valid("query").autosave === "true" },
  )), 200));

  app.openapi(createRoute({
    method: "delete", path: "/v1/posts/{id}", operationId: "deletePost", tags: ["Posts"], security,
    description: "Deletes a draft with its history and images. A scheduled or published post is refused; unpublish it first.",
    request: { params: idParam },
    responses: { 204: { description: "The draft is gone" }, 401: errors[401], 403: errors[403], 404: errors[404], 409: errors[409] },
  }), async (context) => {
    await deletePost(db, context.req.valid("param").id);
    return context.body(null, 204);
  });

  app.openapi(createRoute({
    method: "post", path: "/v1/posts/{id}/schedule", operationId: "schedulePost", tags: ["Lifecycle"], security,
    description: "Validates and renders the post now and publishes it at publishedAt. A token needs the owner's approval of the post as it is (403 approval_required or approval_lapsed).",
    request: { params: idParam, body: { required: true, content: { "application/json": { schema: z.object({ publishedAt: z.iso.datetime() }) } } } },
    responses: { 200: json(postSchema, "The scheduled post"), ...errors },
  }), async (context) => context.json(serialize(await schedulePost(
    cms, context.req.valid("param").id, new Date(context.req.valid("json").publishedAt), context.var.actor,
  )), 200));

  app.openapi(createRoute({
    method: "post", path: "/v1/posts/{id}/approve", operationId: "approvePost", tags: ["Lifecycle"], security,
    description: "The owner, signed in to the admin, approves the post as reviewed, so an agent may schedule or publish it. Tokens are refused, also with posts:publish.",
    request: {
      params: idParam,
      body: { required: true, content: { "application/json": { schema: z.object({ contentHash: z.string().describe("The post's contentHash as the owner reviewed it") }) } } },
    },
    responses: { 200: json(postSchema, "The approved post"), 401: errors[401], 403: json(errorSchema, "Not the owner"), 404: errors[404], 409: json(errorSchema, "The post changed after the review") },
  }), async (context) => context.json(serialize(await approvePost(
    db, context.req.valid("param").id, context.req.valid("json").contentHash, context.var.actor,
  )), 200));

  app.openapi(createRoute({
    method: "post", path: "/v1/posts/{id}/publish", operationId: "publishPost", tags: ["Lifecycle"], security,
    description: "Publishes the post now. A token needs the owner's approval of the post as it is (403 approval_required or approval_lapsed).",
    request: { params: idParam },
    responses: { 200: json(postSchema, "The published post"), ...errors },
  }), async (context) => context.json(serialize(await publishPost(cms, context.req.valid("param").id, context.var.actor)), 200));

  app.openapi(createRoute({
    method: "post", path: "/v1/posts/{id}/unpublish", operationId: "unpublishPost", tags: ["Lifecycle"], security,
    description: "Returns the post to draft. Only the owner; tokens get 403 owner_only.",
    request: { params: idParam },
    responses: { 200: json(postSchema, "The post, back to draft"), 401: errors[401], 403: errors[403], 404: errors[404] },
  }), async (context) => context.json(serialize(await unpublishPost(db, context.req.valid("param").id, context.var.actor)), 200));

  const renditionSchema = z.object({
    heading: z.string(), html: z.string(), toc: z.array(z.object({ id: z.string(), text: z.string() })), readingMinutes: z.number().int(),
  });
  app.openapi(createRoute({
    method: "post", path: "/v1/posts/{id}/preview", operationId: "previewPost", tags: ["Posts"], security,
    description: "Renders the post with the given unsaved changes as it would go live, and lists what the article contract refuses. Saves nothing.",
    request: { params: idParam, body: { required: true, content: { "application/json": { schema: postPatch } } } },
    responses: {
      200: json(z.object({ problems: z.array(z.string()), rendition: renditionSchema.nullable() }).openapi("Preview"), "The rendering and the contract's problems"),
      401: errors[401], 403: errors[403], 404: errors[404],
    },
  }), async (context) => context.json(await previewPost(cms, context.req.valid("param").id, context.req.valid("json")), 200));

  app.openapi(createRoute({
    method: "get", path: "/v1/posts/{id}/revisions", operationId: "listRevisions", tags: ["Revisions"], security,
    request: { params: idParam },
    responses: { 200: json(z.object({ revisions: z.array(revisionSchema) }), "Revisions, newest first"), 401: errors[401], 403: errors[403], 404: errors[404] },
  }), async (context) => {
    const revisions = await listRevisions(db, context.req.valid("param").id);
    return context.json({ revisions: revisions.map((revision) => revisionSchema.parse({ ...revision, createdAt: revision.createdAt.toISOString() })) }, 200);
  });

  app.openapi(createRoute({
    method: "post", path: "/v1/posts/{id}/revisions/{revisionId}/restore", operationId: "restoreRevision", tags: ["Revisions"], security,
    request: { params: idParam.extend({ revisionId: z.uuid() }) },
    responses: { 200: json(postSchema, "The post with the revision's content"), ...errors },
  }), async (context) => {
    const { id, revisionId } = context.req.valid("param");
    return context.json(serialize(await restoreRevision(cms, id, revisionId, context.var.actor)), 200);
  });

  const mediaSchema = z.object({
    id: z.uuid(), name: z.string(), contentType: z.string(), sha256: z.string(),
    sizeBytes: z.number().int(), width: z.number().int(), height: z.number().int(), createdAt: z.iso.datetime(),
  }).openapi("Media");
  const serializeMedia = (row: Awaited<ReturnType<typeof listMedia>>[number]) => mediaSchema.parse({ ...row, createdAt: row.createdAt.toISOString() });

  app.use("/v1/posts/:id/media", requireScope(db, "posts:read"));
  app.use("/v1/posts/:id/media/:name", requireScope(db, "posts:write"));
  app.use("/v1/posts/:id/media/:name", bodyLimit({
    maxSize: maxImageBytes,
    onError: (context) => context.json({ error: { code: "too_large", message: "Images may be at most 10 MB." } }, 413),
  }));

  app.openapi(createRoute({
    method: "get", path: "/v1/posts/{id}/media", operationId: "listMedia", tags: ["Media"], security,
    request: { params: idParam },
    responses: { 200: json(z.object({ media: z.array(mediaSchema) }), "Images of the post, by name"), 401: errors[401], 403: errors[403], 404: errors[404] },
  }), async (context) => {
    const { id } = context.req.valid("param");
    await getPost(db, id);
    return context.json({ media: (await listMedia(db, id)).map(serializeMedia) }, 200);
  });

  const binary = z.string().openapi({ type: "string", format: "binary" });
  app.openapi(createRoute({
    method: "put", path: "/v1/posts/{id}/media/{name}", operationId: "uploadMedia", tags: ["Media"], security,
    description: "Stores an image the post's Markdown references as media/<slug>/<name>. Sending the same name again replaces it. Tokens add images to drafts only (403 live_post).",
    request: {
      params: idParam.extend({ name: z.string() }),
      body: { required: true, content: { "image/png": { schema: binary }, "image/jpeg": { schema: binary }, "image/webp": { schema: binary } } },
    },
    responses: { 200: json(mediaSchema, "The stored image"), 401: errors[401], 403: errors[403], 404: errors[404], 413: json(errorSchema, "Larger than 10 MB"), 422: json(errorSchema, "Not a valid image or name") },
  }), async (context) => {
    const { id, name } = context.req.valid("param");
    await getPost(db, id);
    const bytes = new Uint8Array(await context.req.arrayBuffer());
    const row = await uploadMedia(cms, id, name, bytes, context.req.header("content-type") ?? "", context.var.actor);
    return context.json(serializeMedia(row), 200);
  });

  return app;
}
