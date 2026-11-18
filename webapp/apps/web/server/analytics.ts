// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The blog funnel's measurements (PRD R10): page views and download clicks
// through Umami's tracker, and downloads counted here at /download, where an
// ad blocker cannot hide them. Umami is reached through this origin (/stats),
// as Umami documents for proxying, so the Content Security Policy stays
// 'self'. The proxy forwards the request body and the browser's User-Agent
// (Umami ignores bots by it), never the visitor's IP address.
import type { Env, Hono } from "hono";
import { bodyLimit } from "hono/body-limit";
import type { ServerConfig } from "./config";
import { RateLimitStore, clientKey, rateLimiter } from "./http/rate-limiter";

export type Analytics = NonNullable<ServerConfig["analytics"]>;
type Fetch = (input: string, init?: RequestInit) => Promise<Response>;

const proxyPath = "/stats";
// A page's path on this site, as download buttons send it; anything else is not recorded.
const pagePath = /^\/[A-Za-z0-9._~/-]{0,200}$/;

/** The tracker's script tag. Search and hash are left out of what it records; Do Not Track is honoured. */
export function analyticsTag(analytics: Analytics, publicBaseUrl: string) {
  const attributes = {
    src: `${proxyPath}/script.js`,
    "data-website-id": analytics.websiteId,
    "data-host-url": proxyPath,
    "data-domains": new URL(publicBaseUrl).hostname,
    "data-exclude-search": "true",
    "data-exclude-hash": "true",
    "data-do-not-track": "true",
  };
  return `<script defer ${Object.entries(attributes).map(([name, value]) => `${name}="${value}"`).join(" ")}></script>`;
}

/** Adds the tracker to a rendered page, at the end of its head. */
export function withAnalytics(html: string, tag: string) {
  return html.includes("</head>") ? html.replace("</head>", `${tag}</head>`) : html;
}

/** Whether the browser asks not to be tracked (Do Not Track or Global Privacy Control). */
const declinesTracking = (headers: Headers) => headers.get("dnt") === "1" || headers.get("sec-gpc") === "1";

export function registerAnalytics<E extends Env>(app: Hono<E>, input: {
  analytics?: Analytics;
  publicBaseUrl: string;
  /** The exact immutable DMG of the latest release, or none while the catalog is empty. */
  downloadURL?: string;
  fetcher?: Fetch;
  log?: (message: string) => void;
}) {
  const fetcher = input.fetcher ?? fetch;
  const log = input.log ?? ((message: string) => console.warn(JSON.stringify({ level: "warn", message })));
  const hostname = new URL(input.publicBaseUrl).hostname;
  // The download always works; a client repeating it is counted a few times a minute at most.
  const counted = new RateLimitStore({ windowMs: 60_000, limit: 5 });

  app.get("/download", (context) => {
    context.header("cache-control", "no-store");
    context.header("x-robots-tag", "noindex, nofollow");
    if (!input.downloadURL) return context.redirect("/releases", 302);
    const from = context.req.query("from");
    const { analytics } = input;
    if (analytics && !declinesTracking(context.req.raw.headers) && counted.consume(clientKey(context)).allowed) {
      // Never delays the download: the event is sent after the redirect, and a failure is only logged.
      void send(fetcher, analytics, {
        type: "event",
        payload: { website: analytics.websiteId, hostname, url: from && pagePath.test(from) ? from : "/download", name: "download" },
      }, context.req.header("user-agent") ?? "").then(
        (response) => { if (!response.ok) log(`Umami refused a download event: ${response.status}`); },
        (error: unknown) => log(`Umami unreachable for a download event: ${String(error)}`),
      );
    }
    return context.redirect(input.downloadURL, 302);
  });

  const { analytics } = input;
  if (!analytics) return;
  let script: { body: string; expires: number } | undefined;
  app.get(`${proxyPath}/script.js`, async (context) => {
    if (!script || script.expires < Date.now()) {
      const response = await fetcher(`${analytics.umamiUrl}/script.js`, { signal: AbortSignal.timeout(5_000) }).catch(() => undefined);
      if (!response?.ok) {
        context.header("cache-control", "no-store");
        return context.body("", 503);
      }
      script = { body: await response.text(), expires: Date.now() + 3_600_000 };
    }
    context.header("content-type", "text/javascript; charset=utf-8");
    context.header("cache-control", "public, max-age=3600");
    return context.body(script.body);
  });
  app.use(`${proxyPath}/api/send`, rateLimiter({ windowMs: 60_000, limit: 120 }));
  app.post(`${proxyPath}/api/send`, bodyLimit({ maxSize: 8_192 }), async (context) => {
    context.header("cache-control", "no-store");
    const body = await context.req.text();
    const response = await fetcher(`${analytics.umamiUrl}/api/send`, {
      method: "POST",
      headers: { "content-type": "application/json", "user-agent": context.req.header("user-agent") ?? "" },
      body,
      signal: AbortSignal.timeout(5_000),
    }).catch(() => undefined);
    if (!response) return context.body(null, 502);
    return context.body(await response.text(), response.status as 200);
  });
}

function send(fetcher: Fetch, analytics: Analytics, event: object, userAgent: string) {
  return fetcher(`${analytics.umamiUrl}/api/send`, {
    method: "POST",
    headers: { "content-type": "application/json", "user-agent": userAgent },
    body: JSON.stringify(event),
    signal: AbortSignal.timeout(5_000),
  });
}
