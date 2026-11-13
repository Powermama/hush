// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Where image bytes live: a local directory in development and tests, an
// S3-compatible bucket (Cloudflare R2) in production. Postgres keeps only the
// records. Keys are content hashes or content-hashed paths, so a write is
// idempotent and never changes what an existing key serves.
import { S3Client } from "bun";
import { mkdir, rename } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";

export interface MediaStore {
  put(key: string, bytes: Uint8Array, type: string): Promise<void>;
  get(key: string): Promise<Uint8Array | undefined>;
}

export class LocalMediaStore implements MediaStore {
  private readonly root: string;
  constructor(root: string) { this.root = resolve(root); }

  async put(key: string, bytes: Uint8Array) {
    const path = this.path(key);
    await mkdir(dirname(path), { recursive: true });
    // Write then rename, so a reader never sees a partial file.
    const temporary = `${path}.${crypto.randomUUID()}.tmp`;
    await Bun.write(temporary, bytes);
    await rename(temporary, path);
  }

  async get(key: string) {
    const file = Bun.file(this.path(key));
    return await file.exists() ? new Uint8Array(await file.arrayBuffer()) : undefined;
  }

  private path(key: string) {
    const path = resolve(join(this.root, key));
    if (!path.startsWith(`${this.root}/`)) throw new Error(`Media key escapes the store: ${key}`);
    return path;
  }
}

export class S3MediaStore implements MediaStore {
  constructor(private readonly client: S3Client) {}

  async put(key: string, bytes: Uint8Array, type: string) {
    await this.client.write(key, bytes, { type });
  }

  async get(key: string) {
    const file = this.client.file(key);
    return await file.exists() ? new Uint8Array(await file.arrayBuffer()) : undefined;
  }
}

export function createMediaStore(config: { kind: "local"; directory: string } | { kind: "s3"; bucket: string; endpoint: string; accessKeyId: string; secretAccessKey: string }): MediaStore {
  if (config.kind === "local") return new LocalMediaStore(config.directory);
  return new S3MediaStore(new S3Client({
    bucket: config.bucket, endpoint: config.endpoint,
    accessKeyId: config.accessKeyId, secretAccessKey: config.secretAccessKey,
  }));
}
