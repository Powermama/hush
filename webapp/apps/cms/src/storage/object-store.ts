// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Where the CMS keeps files: article images and database backups. A local
// directory in development and tests, an S3-compatible bucket (Cloudflare R2)
// in production. Postgres keeps only records. Image keys are content hashes,
// so writing one again never changes what it serves.
import { S3Client } from "bun";
import { mkdir, readdir, rename, unlink } from "node:fs/promises";
import { dirname, join, relative, resolve } from "node:path";

export interface ObjectStore {
  put(key: string, bytes: Uint8Array, type: string): Promise<void>;
  get(key: string): Promise<Uint8Array | undefined>;
  /** Every key under the prefix, in no particular order. */
  list(prefix: string): Promise<string[]>;
  delete(key: string): Promise<void>;
}

export type ObjectStoreConfig =
  | { kind: "local"; directory: string }
  | { kind: "s3"; bucket: string; endpoint: string; accessKeyId: string; secretAccessKey: string };

export class LocalObjectStore implements ObjectStore {
  private readonly root: string;
  constructor(root: string) { this.root = resolve(root); }

  async put(key: string, bytes: Uint8Array, _type?: string) {
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

  async list(prefix: string) {
    const files = await readdir(this.root, { recursive: true }).catch(() => [] as string[]);
    return files.map((file) => relative(this.root, join(this.root, file)))
      .filter((key) => key.startsWith(prefix) && !key.endsWith(".tmp"));
  }

  async delete(key: string) {
    await unlink(this.path(key)).catch(() => {});
  }

  private path(key: string) {
    const path = resolve(join(this.root, key));
    if (!path.startsWith(`${this.root}/`)) throw new Error(`Key escapes the store: ${key}`);
    return path;
  }
}

export class S3ObjectStore implements ObjectStore {
  constructor(private readonly client: S3Client) {}

  async put(key: string, bytes: Uint8Array, type: string) {
    await this.client.write(key, bytes, { type });
  }

  async get(key: string) {
    const file = this.client.file(key);
    return await file.exists() ? new Uint8Array(await file.arrayBuffer()) : undefined;
  }

  async list(prefix: string) {
    const keys: string[] = [];
    let startAfter: string | undefined;
    for (;;) {
      const page = await this.client.list({ prefix, startAfter, maxKeys: 1000 });
      const batch = (page.contents ?? []).map((object) => object.key);
      keys.push(...batch);
      if (!page.isTruncated || !batch.length) return keys;
      startAfter = batch.at(-1);
    }
  }

  async delete(key: string) {
    await this.client.delete(key);
  }
}

export function createObjectStore(config: ObjectStoreConfig): ObjectStore {
  if (config.kind === "local") return new LocalObjectStore(config.directory);
  return new S3ObjectStore(new S3Client({
    bucket: config.bucket, endpoint: config.endpoint,
    accessKeyId: config.accessKeyId, secretAccessKey: config.secretAccessKey,
  }));
}
