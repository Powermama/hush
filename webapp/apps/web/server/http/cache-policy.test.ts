import { describe, expect, test } from "bun:test";
import {
  HTML_CACHE_CONTROL,
  cacheControlForStaticPath,
} from "./cache-policy";

describe("website cache policy", () => {
  test("always revalidates the application shell", () => {
    expect(cacheControlForStaticPath("/index.html")).toBe(HTML_CACHE_CONTROL);
  });

  test("keeps content-hashed assets immutable", () => {
    expect(cacheControlForStaticPath("/assets/index-abc123.js")).toBe(
      "public, max-age=31536000, immutable",
    );
  });

  test("briefly caches other public files", () => {
    expect(cacheControlForStaticPath("/robots.txt")).toBe(
      "public, max-age=300",
    );
  });

  test("preserves precompressed binary archives without proxy recompression", () => {
    expect(cacheControlForStaticPath("/assets/studio-lighting.ktx2-abc123.gz")).toBe(
      "public, max-age=31536000, immutable, no-transform",
    );
  });

  test("never caches the blog's CMS revision, which the CMS polls", () => {
    expect(cacheControlForStaticPath("./dist/blog/revision.txt")).toBe("no-store");
  });
});
