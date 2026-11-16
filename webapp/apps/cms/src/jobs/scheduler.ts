// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The CMS's clock, run as its own process (cms-scheduler in Compose; a CronJob
// on Kubernetes): every minute it publishes scheduled posts that are due,
// deploys the website when it is behind the CMS and tells search engines about
// changed pages (src/site/deploy.ts), and whenever the newest backup is a day
// old it takes a new one. Both steps are
// idempotent, so a restart or a second instance (during a rolling update) does
// no harm. Like the API it answers health checks over HTTP on PORT (3100):
// /health/live while it runs, /health/ready while its last tick without errors
// is under five minutes old (or it started less than five minutes ago) and its
// backup bucket has answered (config-check.ts), so the
// image's health check and any platform's probe work for it unchanged. It
// applies pending migrations before its first tick,
// as the API does at start (under one advisory lock), so neither depends on
// the other having started.
import { backupDatabase, backupTime, listBackups } from "../backups/backups";
import { loadConfig } from "../config";
import { storeCheck, watchConfiguration } from "../config-check";
import { connectDatabase } from "../db/client";
import { migrateDatabase } from "../db/migrate";
import { publishDuePosts } from "../posts/service";
import { syncSite } from "../site/deploy";
import { createObjectStore } from "../storage/object-store";

/** How long the scheduler counts as ready without a tick that succeeded. */
const readyWindowMs = 5 * 60_000;

const config = loadConfig();
await migrateDatabase(config.databaseUrl);
const { db, close } = connectDatabase(config.databaseUrl);
const backups = createObjectStore(config.backups);
// Not ready until the backup bucket answers with these credentials (config-check.ts).
const configuration = watchConfiguration([storeCheck("backup bucket", backups)]);
const log = (level: "info" | "error", message: string, details: Record<string, unknown> = {}) =>
  console[level](JSON.stringify({ level, message, ...details }));

let stopping = false;
process.on("SIGTERM", () => { stopping = true; });

const startedAt = Date.now();
let lastHealthyTick: number | undefined;
const health = Bun.serve({
  port: Number(process.env.PORT ?? 3100),
  fetch(request) {
    const { pathname } = new URL(request.url);
    if (pathname === "/health/live") return Response.json({ status: "ok" });
    if (pathname === "/health/ready") {
      const ready = !stopping && configuration.configured() && Date.now() - (lastHealthyTick ?? startedAt) < readyWindowMs;
      return Response.json({ status: ready ? "ready" : "not ready" }, { status: ready ? 200 : 503 });
    }
    return new Response("Not found", { status: 404 });
  },
});

async function tick() {
  let healthy = true;
  try {
    const published = await publishDuePosts(db);
    if (published.length) log("info", "Published due posts", { slugs: published.map((post) => `${post.lang}/${post.slug}`) });
  } catch (error) {
    healthy = false;
    log("error", "Publishing due posts failed", { error: String(error) });
  }
  if (config.site) {
    try {
      const { live, notified, deployRequested } = await syncSite(db, config.site);
      if (deployRequested) log("info", "Requested a website deploy", { liveRevision: live });
      if (notified.length) log("info", "Submitted changed pages to IndexNow", { urls: notified });
    } catch (error) {
      healthy = false;
      log("error", "Syncing the website failed", { error: String(error) });
    }
  }
  try {
    const newest = (await listBackups(backups))[0];
    const age = newest ? Date.now() - backupTime(newest)!.getTime() : Infinity;
    if (age >= 86_400_000) log("info", "Backed up the CMS database", await backupDatabase(config.databaseUrl, backups, config.backups.keepDays));
  } catch (error) {
    healthy = false;
    log("error", "Backing up the CMS database failed", { error: String(error) });
  }
  if (healthy) lastHealthyTick = Date.now();
}

log("info", "hush CMS scheduler started");
while (!stopping) {
  await tick();
  for (let waited = 0; waited < 60_000 && !stopping; waited += 1_000) await Bun.sleep(1_000);
}
configuration.stop();
await health.stop(true);
await close();
