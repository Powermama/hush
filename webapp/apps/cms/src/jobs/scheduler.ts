// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The CMS's clock, run as its own process (cms-scheduler in Compose; a CronJob
// on Kubernetes): every minute it publishes scheduled posts that are due, and
// whenever the newest backup is a day old it takes a new one. Both steps are
// idempotent, so a restart or a second instance does no harm.
import { backupDatabase, backupTime, listBackups } from "../backups/backups";
import { loadConfig } from "../config";
import { connectDatabase } from "../db/client";
import { publishDuePosts } from "../posts/service";
import { createObjectStore } from "../storage/object-store";

const config = loadConfig();
const { db, close } = connectDatabase(config.databaseUrl);
const backups = createObjectStore(config.backups);
const log = (level: "info" | "error", message: string, details: Record<string, unknown> = {}) =>
  console[level](JSON.stringify({ level, message, ...details }));

let stopping = false;
process.on("SIGTERM", () => { stopping = true; });

async function tick() {
  try {
    const published = await publishDuePosts(db);
    if (published.length) log("info", "Published due posts", { slugs: published.map((post) => `${post.lang}/${post.slug}`) });
  } catch (error) {
    log("error", "Publishing due posts failed", { error: String(error) });
  }
  try {
    const newest = (await listBackups(backups))[0];
    const age = newest ? Date.now() - backupTime(newest)!.getTime() : Infinity;
    if (age >= 86_400_000) log("info", "Backed up the CMS database", await backupDatabase(config.databaseUrl, backups, config.backups.keepDays));
  } catch (error) {
    log("error", "Backing up the CMS database failed", { error: String(error) });
  }
}

log("info", "hush CMS scheduler started");
while (!stopping) {
  await tick();
  for (let waited = 0; waited < 60_000 && !stopping; waited += 1_000) await Bun.sleep(1_000);
}
await close();
