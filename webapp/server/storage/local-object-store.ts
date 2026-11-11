import { mkdir, unlink } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import type { ProofObjectStore, UploadTarget } from "./proof-object-store";

export class LocalProofObjectStore implements ProofObjectStore {
  private readonly root: string;

  constructor(
    root: string,
    private readonly publicBaseUrl: string,
  ) {
    this.root = resolve(root);
  }

  async createUploadTarget(input: {
    objectKey: string;
    proofId: string;
    uploadToken: string;
    contentLength: number;
    contentType: string;
  }): Promise<UploadTarget> {
    const url = new URL(`/v1/proofs/${input.proofId}/content`, this.publicBaseUrl);
    url.searchParams.set("token", input.uploadToken);
    return {
      url: url.toString(),
      headers: { "content-type": input.contentType },
    };
  }

  async put(objectKey: string, bytes: Uint8Array): Promise<void> {
    const path = this.pathFor(objectKey);
    await mkdir(dirname(path), { recursive: true });
    await Bun.write(path, bytes);
  }

  async get(objectKey: string): Promise<Uint8Array | null> {
    const file = Bun.file(this.pathFor(objectKey));
    if (!(await file.exists())) return null;
    return new Uint8Array(await file.arrayBuffer());
  }

  async delete(objectKey: string): Promise<void> {
    try {
      await unlink(this.pathFor(objectKey));
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
    }
  }

  private pathFor(objectKey: string): string {
    if (!/^proofs\/[0-9a-f-]+\.bin$/.test(objectKey)) {
      throw new Error("Invalid proof object key");
    }
    const path = resolve(join(this.root, objectKey));
    if (!path.startsWith(`${this.root}/`)) throw new Error("Unsafe object path");
    return path;
  }
}

