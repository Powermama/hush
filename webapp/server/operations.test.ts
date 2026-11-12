// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { afterEach, describe, expect, test } from "bun:test";
import { mkdtemp, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createApp } from "./app";
import { createEphemeralServiceKey } from "./crypto/p256";
import { SQLiteProofRepository } from "./repositories/sqlite-proof-repository";
import { ProofService } from "./services/proof-service";
import { LocalProofObjectStore } from "./storage/local-object-store";

async function appWith(options: Partial<Parameters<typeof createApp>[0]>) {
  const repository = new SQLiteProofRepository();
  const directory = await mkdtemp(join(tmpdir(), "hush-ops-"));
  const objects = new LocalProofObjectStore(directory, "http://hush.test");
  const service = new ProofService(repository, objects, await createEphemeralServiceKey(), "http://hush.test");
  return { repository, directory, app: createApp({ proofService: service, allowedOrigin: "http://hush.test", ...options }) };
}

describe("operations for zero-downtime deployments", () => {
  const cleanups: Array<() => Promise<void> | void> = [];
  afterEach(async () => {
    for (const cleanup of cleanups.splice(0)) await cleanup();
  });

  test("readiness reports the instance state truthfully and is never cached", async () => {
    let ready = true;
    const { app, repository, directory } = await appWith({ readiness: async () => ready });
    cleanups.push(() => repository.close(), () => rm(directory, { recursive: true, force: true }));

    const healthy = await app.request("/health/ready");
    expect(healthy.status).toBe(200);
    expect(healthy.headers.get("cache-control")).toBe("no-store");
    ready = false;
    expect((await app.request("/health/ready")).status).toBe(503);
    // Liveness stays up while draining, so Docker does not kill a draining instance early.
    expect((await app.request("/health/live")).status).toBe(200);
  });

  test("a failing readiness check is reported as not ready, not as a server error", async () => {
    const { app, repository, directory } = await appWith({ readiness: async () => { throw new Error("database down"); } });
    cleanups.push(() => repository.close(), () => rm(directory, { recursive: true, force: true }));
    const response = await app.request("/health/ready");
    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({ status: "unavailable" });
  });

  test("read-only mode pauses proof writes and keeps reads available", async () => {
    const { app, repository, directory } = await appWith({ readOnly: true });
    cleanups.push(() => repository.close(), () => rm(directory, { recursive: true, force: true }));

    const write = await app.request("/v1/enrollment-challenges", { method: "POST" });
    expect(write.status).toBe(503);
    expect(write.headers.get("retry-after")).toBe("300");
    expect((await write.json()).error.code).toBe("read_only");
    const read = await app.request("/v1/proofs/does-not-exist");
    expect(read.status).not.toBe(503);
    expect((await app.request("/health/ready")).status).toBe(200);
  });

  test("local proof objects are written atomically", async () => {
    const directory = await mkdtemp(join(tmpdir(), "hush-objects-"));
    cleanups.push(() => rm(directory, { recursive: true, force: true }));
    const store = new LocalProofObjectStore(directory, "http://hush.test");
    const key = "proofs/0f8fad5b-d9cb-469f-a165-70867728950e.bin";
    await store.put(key, new Uint8Array([1, 2, 3]));
    await store.put(key, new Uint8Array([4, 5]));
    expect(await store.get(key)).toEqual(new Uint8Array([4, 5]));
    // No temporary files are left beside the object.
    expect(await readdir(join(directory, "proofs"))).toEqual(["0f8fad5b-d9cb-469f-a165-70867728950e.bin"]);
  });
});

describe("graceful shutdown of the real server process", () => {
  test("keeps serving while draining, reports not ready, then exits cleanly", async () => {
    const port = 41_000 + Math.floor(Math.random() * 1_000);
    const base = `http://127.0.0.1:${port}`;
    const child = Bun.spawn(["bun", "server/index.ts"], {
      env: { ...process.env, NODE_ENV: "test", PORT: String(port), HUSH_SHUTDOWN_DRAIN_MS: "1500" },
      stdout: "pipe",
      stderr: "pipe",
    });
    try {
      // Shared CI runners can take several seconds to start a Bun process.
      const readyBy = Date.now() + 30_000;
      for (;;) {
        try { if ((await fetch(`${base}/health/ready`)).ok) break; } catch {}
        if (Date.now() > readyBy || child.exitCode !== null) {
          child.kill("SIGKILL");
          const output = `${await new Response(child.stdout).text()}${await new Response(child.stderr).text()}`;
          throw new Error(`server did not become ready (exit ${child.exitCode}):\n${output.slice(-2_000)}`);
        }
        await Bun.sleep(100);
      }
      expect((await fetch(`${base}/health/live`)).headers.get("connection")).not.toBe("close");
      const started = Date.now();
      child.kill("SIGTERM");
      await Bun.sleep(200);
      // During the drain the instance still answers requests the proxy routes to it.
      const live = await fetch(`${base}/health/live`);
      expect(live.status).toBe(200);
      // The proxy must stop reusing keep-alive connections to a draining instance.
      expect(live.headers.get("connection")).toBe("close");
      expect((await fetch(`${base}/health/ready`)).status).toBe(503);
      expect(await child.exited).toBe(0);
      const elapsed = Date.now() - started;
      expect(elapsed).toBeGreaterThanOrEqual(1_400);
      expect(elapsed).toBeLessThan(10_000);
    } finally {
      child.kill("SIGKILL");
    }
  }, 60_000);
});
