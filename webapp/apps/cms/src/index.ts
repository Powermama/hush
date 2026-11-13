// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { createApp } from "./app";
import { connectDatabase } from "./db/client";
import { migrateDatabase } from "./db/migrate";
import { loadConfig } from "./config";
import { createMediaStore } from "./media/store";

const config = loadConfig();
await migrateDatabase(config.databaseUrl);
const { db, close } = connectDatabase(config.databaseUrl);
let draining = false;
const app = createApp({ db, media: createMediaStore(config.media) }, { isDraining: () => draining });
const server = Bun.serve({ port: config.port, fetch: app.fetch });
console.info(JSON.stringify({ level: "info", message: "hush CMS listening", port: server.port, environment: config.environment }));

// Report not-ready first so the proxy stops routing here, then finish requests.
process.on("SIGTERM", async () => {
  draining = true;
  await Bun.sleep(Number(process.env.CMS_SHUTDOWN_DRAIN_MS ?? 5_000));
  await server.stop();
  await close();
  process.exit(0);
});
