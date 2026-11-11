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

  test("generates and reuses a persistent production signing key", async () => {
    const dataDirectory = await mkdtemp(join(tmpdir(), "hush-service-key-"));
    try {
      const config = loadConfig({
        NODE_ENV: "production",
        HUSH_PUBLIC_BASE_URL: "https://behu.sh",
        HUSH_SHORT_BASE_URL: "https://behu.sh",
        HUSH_DATA_DIR: dataDirectory,
        HUSH_SERVICE_KEY_ID: "hush-production-1",
      });

      const first = await loadServiceKey(config);
      const second = await loadServiceKey(config);

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
});
