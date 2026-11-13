// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { expect, test } from "bun:test";
import { S3ProofObjectStore } from "./s3-object-store";

test("S3-compatible storage signs uploads and preserves encrypted bytes and missing-object handling", async () => {
  const objects = new Map<string, Uint8Array>();
  const server = Bun.serve({
    hostname: "127.0.0.1", port: 0,
    async fetch(request) {
      const path = new URL(request.url).pathname;
      if (!request.headers.get("authorization")?.startsWith("AWS4-HMAC-SHA256 ")) {
        return new Response(null, { status: 403 });
      }
      if (request.method === "PUT") {
        objects.set(path, new Uint8Array(await request.arrayBuffer()));
        return new Response(null, { status: 200 });
      }
      if (request.method === "DELETE") {
        objects.delete(path);
        return new Response(null, { status: 204 });
      }
      const bytes = objects.get(path);
      return bytes ? new Response(Uint8Array.from(bytes).buffer) : new Response(
        '<?xml version="1.0"?><Error><Code>NoSuchKey</Code><Message>Missing fixture</Message></Error>',
        { status: 404, headers: { "content-type": "application/xml" } },
      );
    },
  });
  try {
    const store = new S3ProofObjectStore("test-proofs", {
      region: "auto", endpoint: server.url.toString(),
      accessKeyId: "test-access-key", secretAccessKey: "test-secret-key",
    });
    const bytes = Uint8Array.from([0, 255, 1, 128, 42]);
    const target = await store.createUploadTarget({
      objectKey: "fixture.bin", proofId: "fixture", uploadToken: "fixture",
      contentLength: bytes.length, contentType: "application/vnd.hush.proof+encrypted",
    });
    const url = new URL(target.url);
    expect(url.origin).toBe(server.url.origin);
    expect(url.pathname).toBe("/test-proofs/fixture.bin");
    expect(url.searchParams.get("X-Amz-Expires")).toBe("300");
    expect(url.searchParams.get("X-Amz-Signature")).toMatch(/^[a-f0-9]{64}$/);
    expect(target.headers["content-type"]).toBe("application/vnd.hush.proof+encrypted");
    await store.put("fixture.bin", bytes);
    expect(await store.get("fixture.bin")).toEqual(bytes);
    await store.delete("fixture.bin");
    expect(await store.get("fixture.bin")).toBeNull();
  } finally {
    await server.stop(true);
  }
});
