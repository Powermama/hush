import { describe, expect, test } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { loadConfig, loadServiceKey } from "./config";

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

  test("generates a production signing key only when bootstrapping, then reuses it", async () => {
    const dataDirectory = await mkdtemp(join(tmpdir(), "hush-service-key-"));
    try {
      const production = {
        NODE_ENV: "production",
        HUSH_PUBLIC_BASE_URL: "https://behu.sh",
        HUSH_SHORT_BASE_URL: "https://behu.sh",
        HUSH_DATA_DIR: dataDirectory,
        HUSH_SERVICE_KEY_ID: "hush-production-1",
      };
      const config = loadConfig({ ...production, HUSH_ALLOW_SERVICE_KEY_BOOTSTRAP: "1" });

      const first = await loadServiceKey(config);
      // A normal production start without the bootstrap flag reuses the stored key.
      const second = await loadServiceKey(loadConfig(production));

      expect(first.id).toBe("hush-production-1");
      expect(second.id).toBe(first.id);
      expect(second.publicJwk).toEqual(first.publicJwk);
      expect(await Bun.file(join(dataDirectory, "service-key.json")).exists()).toBe(
        true,
      );
    } finally {
      await rm(dataDirectory, { recursive: true, force: true });
    }
  });

  test("fails closed when a production signing key is missing", async () => {
    const dataDirectory = await mkdtemp(join(tmpdir(), "hush-service-key-"));
    try {
      const config = loadConfig({
        NODE_ENV: "production",
        HUSH_PUBLIC_BASE_URL: "https://behu.sh",
        HUSH_SHORT_BASE_URL: "https://behu.sh",
        HUSH_DATA_DIR: dataDirectory,
      });
      await expect(loadServiceKey(config)).rejects.toThrow("Service signing key not found");
      // Nothing is written, so a mis-mounted volume cannot gain a new identity.
      expect(await Bun.file(join(dataDirectory, "service-key.json")).exists()).toBe(false);
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
