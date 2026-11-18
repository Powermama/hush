import { describe, expect, test } from "bun:test";
import { Hono } from "hono";
import { analyticsTag, registerAnalytics, withAnalytics } from "./analytics";
import { loadConfig } from "./config";

const analytics = { umamiUrl: "https://umami.example", websiteId: "0b6a3f0e-8c1d-4b8e-9d55-0d6c1e2f3a4b" };
const dmg = "https://updates.behu.sh/downloads/hush-0.1.0-alpha.5-build.14.dmg";

function setup(options: { analytics?: typeof analytics; downloadURL?: string } = {}) {
  const sent: Array<{ url: string; init?: RequestInit }> = [];
  const app = new Hono();
  registerAnalytics(app, {
    analytics: "analytics" in options ? options.analytics : analytics,
    publicBaseUrl: "https://behu.sh",
    downloadURL: "downloadURL" in options ? options.downloadURL : dmg,
    fetcher: async (url, init) => {
      sent.push({ url, init });
      return url.endsWith("/script.js") ? new Response("/* umami */") : new Response("token", { status: 200 });
    },
    log: () => {},
  });
  return { app, sent };
}

const events = (sent: Array<{ url: string; init?: RequestInit }>) =>
  sent.filter((request) => request.url.endsWith("/api/send")).map((request) => JSON.parse(String(request.init?.body)));

describe("downloads counted at /download (PRD R10)", () => {
  test("redirects to the exact immutable DMG, uncached and unindexed, also without analytics", async () => {
    const { app, sent } = setup({ analytics: undefined });
    const response = await app.request("/download?from=/blog/dictate-on-mac");
    expect(response.status).toBe(302);
    expect(response.headers.get("location")).toBe(dmg);
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(response.headers.get("x-robots-tag")).toBe("noindex, nofollow");
    expect(sent).toEqual([]);
  });

  test("leads to the availability page while the catalog is empty", async () => {
    const { app } = setup({ downloadURL: undefined });
    const response = await app.request("/download?from=/");
    expect(response.headers.get("location")).toBe("/releases");
  });

  test("records a download event with the page it started on and the browser's User-Agent only", async () => {
    const { app, sent } = setup();
    await app.request("/download?from=%2Fde%2Fblog%2Fdiktieren-am-mac", {
      headers: { "user-agent": "Mozilla/5.0 Safari", "cf-connecting-ip": "203.0.113.7" },
    });
    await Bun.sleep(0);
    expect(events(sent)).toEqual([{
      type: "event",
      payload: { website: analytics.websiteId, hostname: "behu.sh", url: "/de/blog/diktieren-am-mac", name: "download" },
    }]);
    const headers = new Headers(sent[0]!.init?.headers);
    expect(headers.get("user-agent")).toBe("Mozilla/5.0 Safari");
    expect([...headers.keys()].sort()).toEqual(["content-type", "user-agent"]);
  });

  test("does not record a page that is not a path on this site", async () => {
    const { app, sent } = setup();
    for (const from of ["https://evil.example/x", "/blog/<script>", ""]) {
      const response = await app.request(`/download?from=${encodeURIComponent(from)}`, { headers: { "cf-connecting-ip": `198.51.100.${from.length}` } });
      expect(response.headers.get("location")).toBe(dmg);
    }
    await Bun.sleep(0);
    expect(events(sent).map((event) => event.payload.url)).toEqual(["/download", "/download", "/download"]);
  });

  test("honours Do Not Track and Global Privacy Control", async () => {
    const { app, sent } = setup();
    await app.request("/download?from=/", { headers: { dnt: "1" } });
    await app.request("/download?from=/", { headers: { "sec-gpc": "1" } });
    await Bun.sleep(0);
    expect(events(sent)).toEqual([]);
  });

  test("counts one client a few times a minute at most, and always redirects", async () => {
    const { app, sent } = setup();
    for (let index = 0; index < 8; index++) {
      const response = await app.request("/download?from=/", { headers: { "cf-connecting-ip": "203.0.113.9" } });
      expect(response.status).toBe(302);
    }
    await Bun.sleep(0);
    expect(events(sent)).toHaveLength(5);
  });

  test("still redirects when Umami is down", async () => {
    const app = new Hono();
    registerAnalytics(app, {
      analytics, publicBaseUrl: "https://behu.sh", downloadURL: dmg,
      fetcher: async () => { throw new Error("connection refused"); }, log: () => {},
    });
    const response = await app.request("/download?from=/");
    expect(response.headers.get("location")).toBe(dmg);
  });
});

describe("Umami through this origin", () => {
  test("adds the tracker to a page, pointed at /stats, with search, hash and Do Not Track respected", () => {
    const tag = analyticsTag(analytics, "https://behu.sh");
    expect(withAnalytics("<html><head><title>x</title></head><body></body></html>", tag))
      .toBe(`<html><head><title>x</title>${tag}</head><body></body></html>`);
    expect(tag).toContain('src="/stats/script.js"');
    expect(tag).toContain('data-host-url="/stats"');
    expect(tag).toContain('data-domains="behu.sh"');
    expect(tag).toContain('data-exclude-search="true"');
    expect(tag).toContain('data-do-not-track="true"');
  });

  test("serves the tracker script and forwards events without the visitor's address", async () => {
    const { app, sent } = setup();
    const script = await app.request("/stats/script.js");
    expect(await script.text()).toBe("/* umami */");
    expect(script.headers.get("content-type")).toContain("javascript");
    const response = await app.request("/stats/api/send", {
      method: "POST", body: JSON.stringify({ type: "event", payload: { url: "/" } }),
      headers: { "content-type": "application/json", "user-agent": "Mozilla/5.0", "cf-connecting-ip": "203.0.113.7", "x-forwarded-for": "203.0.113.7" },
    });
    expect(response.status).toBe(200);
    const forwarded = sent.find((request) => request.url === "https://umami.example/api/send")!;
    expect([...new Headers(forwarded.init?.headers).keys()].sort()).toEqual(["content-type", "user-agent"]);
  });

  test("has no /stats routes while analytics is off", async () => {
    const { app } = setup({ analytics: undefined });
    expect((await app.request("/stats/script.js")).status).toBe(404);
  });
});

describe("analytics configuration", () => {
  test("is off unless both settings are given, and refuses half of it", () => {
    expect(loadConfig({ NODE_ENV: "test" }).analytics).toBeUndefined();
    expect(() => loadConfig({ NODE_ENV: "test", HUSH_UMAMI_URL: "https://umami.example" })).toThrow(/both/);
    expect(loadConfig({ NODE_ENV: "test", HUSH_UMAMI_URL: "https://umami.example/", HUSH_UMAMI_WEBSITE_ID: analytics.websiteId }).analytics)
      .toEqual(analytics);
  });

  test("needs HTTPS in production and the website's UUID", () => {
    const base = { NODE_ENV: "production", HUSH_PUBLIC_BASE_URL: "https://behu.sh" };
    expect(() => loadConfig({ ...base, HUSH_UMAMI_URL: "http://umami.example", HUSH_UMAMI_WEBSITE_ID: analytics.websiteId })).toThrow(/HTTPS/);
    expect(() => loadConfig({ ...base, HUSH_UMAMI_URL: "https://umami.example", HUSH_UMAMI_WEBSITE_ID: "behu.sh" })).toThrow(/UUID/);
  });
});
