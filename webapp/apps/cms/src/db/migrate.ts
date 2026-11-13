// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { drizzle } from "drizzle-orm/postgres-js";
import { migrate } from "drizzle-orm/postgres-js/migrator";
import { join } from "node:path";
import postgres from "postgres";

// One session holds an advisory lock for the whole migration, so two instances
// starting together never apply the same migration twice. Migrations stay
// additive: the previous release keeps running on the new schema until its
// replacement is healthy.
const MIGRATION_LOCK_ID = 7_316_504_212;

export async function migrateDatabase(url: string) {
  const client = postgres(url, { max: 1, prepare: false, onnotice: () => {} });
  try {
    await client`select pg_advisory_lock(${MIGRATION_LOCK_ID})`;
    await migrate(drizzle(client), { migrationsFolder: join(import.meta.dir, "migrations") });
  } finally {
    await client`select pg_advisory_unlock(${MIGRATION_LOCK_ID})`.catch(() => {});
    await client.end({ timeout: 5 });
  }
}

if (import.meta.main) {
  const url = process.env.CMS_DATABASE_URL;
  if (!url) throw new Error("CMS_DATABASE_URL is required");
  await migrateDatabase(url);
  console.info("hush CMS database is current.");
}
