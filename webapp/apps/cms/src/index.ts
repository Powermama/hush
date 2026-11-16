// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { createApp } from "./app";
import { connectDatabase } from "./db/client";
import { migrateDatabase } from "./db/migrate";
import { loadConfig } from "./config";
import { createObjectStore } from "./storage/object-store";

const config = loadConfig();
await migrateDatabase(config.databaseUrl);
const { db, close } = connectDatabase(config.databaseUrl);
let draining = false;
const adminDir = process.env.CMS_ADMIN_DIR ?? "../cms-admin/dist";
const app = createApp({ db, media: createObjectStore(config.media) }, {
  isDraining: () => draining,
  admin: config.admin,
  adminDir: await Bun.file(`${adminDir}/index.html`).exists() ? adminDir : undefined,
});
const server = Bun.serve({ port: config.port, fetch: app.fetch, idleTimeout: 30 });
console.info(JSON.stringify({ level: "info", message: "hush CMS listening", port: server.port, environment: config.environment }));

// Graceful shutdown for rolling updates, as the website's (apps/web/server/index.ts):
// the platform starts the replacement, waits for its health check, then stops this
// instance with a grace period (30 s on Coolify and Kubernetes). Keep answering
// while reporting not-ready, for longer than health checks take to move traffic
// away (three failed checks), then let requests in flight finish, close every
// remaining connection at once and exit inside the grace period.
let stopping = false;
process.on("SIGTERM", async () => {
  if (stopping) return;
  stopping = true;
  draining = true;
  await Bun.sleep(Number(process.env.CMS_SHUTDOWN_DRAIN_MS ?? 10_000));
  const deadline = Date.now() + 10_000;
  while (server.pendingRequests > 0 && Date.now() < deadline) await Bun.sleep(50);
  await server.stop(true);
  await close();
  process.exit(0);
});
