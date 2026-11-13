// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import type { BlogImageOutput } from "@hush/article";
import { and, eq } from "drizzle-orm";
import { createHash } from "node:crypto";
import sharp from "sharp";
import type { Database } from "../db/client";
import { media } from "../db/schema";
import { PostError } from "../posts/errors";
import type { MediaStore } from "./store";

export type Cms = { db: Database; media: MediaStore };

const imageTypes: Record<string, string> = { png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", webp: "image/webp" };
export const maxImageBytes = 10 * 1024 * 1024;
const originalKey = (sha256: string) => `originals/${sha256}`;

/** Stores an image a post references as media/<slug>/<name>, replacing one of the same name. */
export async function uploadMedia(cms: Cms, postId: string, name: string, bytes: Uint8Array, contentType: string) {
  const extension = /^[a-z0-9]+(?:-[a-z0-9]+)*\.(png|jpe?g|webp)$/.exec(name)?.[1];
  if (!extension) throw new PostError(422, "invalid_name", "Name the image like screenshot-name.png (lowercase, digits and dashes; png, jpg or webp).");
  if (imageTypes[extension] !== contentType) throw new PostError(422, "invalid_type", `A .${extension} file must be sent as ${imageTypes[extension]}.`);
  if (bytes.byteLength > maxImageBytes) throw new PostError(422, "too_large", "Images may be at most 10 MB.");
  const { width, height, format } = await sharp(bytes).metadata().catch(() => ({ width: 0, height: 0, format: undefined }));
  if (!width || !height || imageTypes[format === "jpeg" ? "jpg" : format ?? ""] !== contentType) {
    throw new PostError(422, "unreadable_image", "The file is not a readable image of its declared type.");
  }
  const sha256 = createHash("sha256").update(bytes).digest("hex");
  await cms.media.put(originalKey(sha256), bytes, contentType);
  const values = { postId, name, contentType, sha256, sizeBytes: bytes.byteLength, width, height };
  const [row] = await cms.db.insert(media).values(values)
    .onConflictDoUpdate({ target: [media.postId, media.name], set: { ...values, createdAt: new Date() } })
    .returning();
  return row!;
}

export function listMedia(db: Database, postId: string) {
  return db.select().from(media).where(eq(media.postId, postId)).orderBy(media.name);
}

/** Loads an image for the article contract; the source is its storage key. */
export async function loadMedia(cms: Cms, postId: string, slug: string, url: string) {
  const name = new RegExp(`^media/${slug}/([^/]+)$`).exec(url)?.[1];
  if (!name) return undefined;
  const [row] = await cms.db.select().from(media).where(and(eq(media.postId, postId), eq(media.name, name)));
  if (!row) return undefined;
  const bytes = await cms.media.get(originalKey(row.sha256));
  return bytes && { bytes, source: originalKey(row.sha256) };
}

/** Writes the WebP renditions an article's HTML refers to, as the static build does. */
export async function writeRenditions(cms: Cms, images: BlogImageOutput[]) {
  for (const image of images) {
    const key = image.path.replace(/^\//, "");
    if (await cms.media.get(key)) continue; // Content-hashed names: an existing file is current.
    const original = await cms.media.get(image.source);
    if (!original) throw new Error(`Missing original for ${image.path}`);
    await cms.media.put(key, await sharp(original).resize({ width: image.width }).webp({ quality: 82 }).toBuffer(), "image/webp");
  }
}
