// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { expect, test } from "bun:test";
import { Hono } from "hono";
import { rateLimiter, RateLimitStore } from "./rate-limiter";

test("HTTP rate limits reject excess traffic and recover after the window", async () => {
  let now = 1000;
  const app = new Hono();
  app.use("*", rateLimiter({ windowMs: 1000, limit: 2, now: () => now }));
  app.get("/", (c) => c.text("ok"));
  const request = () => app.request("/", { headers: { "cf-connecting-ip": "192.0.2.1" } });
  expect((await request()).status).toBe(200);
  expect((await request()).headers.get("RateLimit-Remaining")).toBe("0");
  expect((await request()).status).toBe(429);
  now += 1000;
  expect((await request()).status).toBe(200);
});

test("storage is bounded without resetting live clients and expires idle IPs", async () => {
  const store = new RateLimitStore({ windowMs: 25, limit: 1, maxEntries: 2 });
  try {
    expect(store.consume("192.0.2.1").allowed).toBe(true);
    expect(store.consume("192.0.2.2").allowed).toBe(true);
    expect(store.consume("192.0.2.3").allowed).toBe(false);
    expect(store.consume("192.0.2.1").allowed).toBe(false);
    expect(store.size).toBe(2);
    // No additional request or explicit sweep drives expiry.
    const deadline = Date.now() + 2000;
    while (store.size && Date.now() < deadline) await Bun.sleep(25);
    expect(store.size).toBe(0);
    expect(store.consume("192.0.2.3").allowed).toBe(true);
  } finally {
    store.dispose();
  }
});
