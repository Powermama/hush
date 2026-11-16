// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { sql } from "drizzle-orm";
import { Hono } from "hono";
import type { Database } from "../db/client";

/** Ready while not draining, the configuration checks have passed (config-check.ts) and the database answers. */
export function healthRoutes(db: Database, isDraining: () => boolean, isConfigured: () => boolean = () => true) {
  const app = new Hono();
  app.get("/health/live", (context) => context.json({ status: "ok" }));
  app.get("/health/ready", async (context) => {
    const ready = !isDraining() && isConfigured() && await Promise.race([
      db.execute(sql`select 1`).then(() => true, () => false),
      Bun.sleep(2_000).then(() => false),
    ]);
    context.header("cache-control", "no-store");
    return ready ? context.json({ status: "ok" }) : context.json({ status: "unavailable" }, 503);
  });
  return app;
}
