import { describe, expect, test } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { loadConfig, loadServiceKey } from "./config";
import { createEphemeralServiceKey } from "./crypto/p256";

describe("proof short-link configuration", () => {
  test("uses the local resolver path by default", () => {
    const config = loadConfig({
      NODE_ENV: "test",
      HUSH_PUBLIC_BASE_URL: "http://127.0.0.1:4173",
    });

    expect(config.shortBaseUrl).toBe("http://127.0.0.1:4173/s/");
  });

  test("derives the production resolver path from the canonical origin", () => {
    const config = loadConfig({
      NODE_ENV: "production",
      HUSH_PUBLIC_BASE_URL: "https://behu.sh",
    });

    expect(config.shortBaseUrl).toBe("https://behu.sh/s/");
    expect(config.allowedOrigin).toBe("https://behu.sh");
  });

  test("normalizes a first-party short domain", () => {
    const config = loadConfig({
      NODE_ENV: "production",
      HUSH_PUBLIC_BASE_URL: "https://verify.hush.app",
      HUSH_SHORT_BASE_URL: "https://behu.sh",
    });

    expect(config.shortBaseUrl).toBe("https://behu.sh/");
  });

  test("rejects insecure production and credential-bearing domains", () => {
    expect(() =>
      loadConfig({
        NODE_ENV: "production",
        HUSH_SHORT_BASE_URL: "http://behu.sh",
      }),
    ).toThrow("must use HTTPS in production");
    expect(() =>
      loadConfig({
        NODE_ENV: "test",
        HUSH_SHORT_BASE_URL: "https://user:secret@behu.sh/",
      }),
    ).toThrow("must not contain credentials");
  });

  test("generates the signing key on first start, reuses it, and keeps every public key", async () => {
    const dataDirectory = await mkdtemp(join(tmpdir(), "hush-service-key-"));
    try {
      const production = loadConfig({
        NODE_ENV: "production",
        HUSH_PUBLIC_BASE_URL: "https://behu.sh",
        HUSH_SHORT_BASE_URL: "https://behu.sh",
        HUSH_DATA_DIR: dataDirectory,
        HUSH_SERVICE_KEY_ID: "hush-production-1",
      });
      const first = await loadServiceKey(production);
      const second = await loadServiceKey(production);
      // Generated keys name themselves by fingerprint, so a replacement never reuses an id.
      expect(first.id).toMatch(/^hush-[A-Za-z0-9_-]{16}$/);
      expect(second.id).toBe(first.id);
      expect(second.publicJwk).toEqual(first.publicJwk);

      // Rotation: delete the private key and restart. A new key signs from now
      // on; the old public key stays known for the receipts it signed.
      await rm(join(dataDirectory, "service-key.json"));
      const rotated = await loadServiceKey(production);
      expect(rotated.id).not.toBe(first.id);
      expect(rotated.publicKeys).toEqual({ [first.id]: first.publicJwk, [rotated.id]: rotated.publicJwk });
      const stored = await Bun.file(join(dataDirectory, "service-public-keys.json")).json();
      expect(Object.keys(stored).sort()).toEqual([first.id, rotated.id].sort());
      expect(JSON.stringify(stored)).not.toContain('"d"');
    } finally {
      await rm(dataDirectory, { recursive: true, force: true });
    }
  });

  test("keeps an existing key with its original id", async () => {
    const dataDirectory = await mkdtemp(join(tmpdir(), "hush-service-key-"));
    try {
      const legacy = await createEphemeralServiceKey();
      const privateJwk = await crypto.subtle.exportKey("jwk", legacy.privateKey);
      await Bun.write(join(dataDirectory, "service-key.json"), JSON.stringify({ id: "hush-production-1", privateJwk }));
      const loaded = await loadServiceKey(loadConfig({
        NODE_ENV: "production",
        HUSH_PUBLIC_BASE_URL: "https://behu.sh",
        HUSH_SHORT_BASE_URL: "https://behu.sh",
        HUSH_DATA_DIR: dataDirectory,
      }));
      expect(loaded.id).toBe("hush-production-1");
      expect(loaded.publicJwk).toEqual(legacy.publicJwk);
      expect(loaded.publicKeys).toEqual({ "hush-production-1": legacy.publicJwk });
    } finally {
      await rm(dataDirectory, { recursive: true, force: true });
    }
  });

  test("reads read-only mode and a bounded shutdown drain", () => {
    expect(loadConfig({ NODE_ENV: "test" })).toMatchObject({ readOnly: false, shutdownDrainMs: 10_000 });
    expect(loadConfig({ NODE_ENV: "test", HUSH_READ_ONLY: "1", HUSH_SHUTDOWN_DRAIN_MS: "2500" }))
      .toMatchObject({ readOnly: true, shutdownDrainMs: 2_500 });
    expect(() => loadConfig({ NODE_ENV: "test", HUSH_SHUTDOWN_DRAIN_MS: "-1" })).toThrow("HUSH_SHUTDOWN_DRAIN_MS");
    expect(() => loadConfig({ NODE_ENV: "test", HUSH_SHUTDOWN_DRAIN_MS: "90000" })).toThrow("HUSH_SHUTDOWN_DRAIN_MS");
  });
});
