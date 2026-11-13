// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Each test file gets its own database on the PostgreSQL server named by
// HUSH_TEST_DATABASE_URL, migrated with the real migrations and dropped after.
import postgres from "postgres";
import { connectDatabase } from "../src/db/client";
import { migrateDatabase } from "../src/db/migrate";

export const serverUrl = process.env.HUSH_TEST_DATABASE_URL;
// CI provides PostgreSQL; never let the CMS contract skip there.
if (process.env.CI && !serverUrl) throw new Error("HUSH_TEST_DATABASE_URL is required in CI");

export async function createTestDatabase() {
  const name = `hush_cms_test_${crypto.randomUUID().replaceAll("-", "")}`;
  const admin = postgres(serverUrl!, { max: 1, onnotice: () => {} });
  await admin.unsafe(`create database ${name}`);
  const url = new URL(serverUrl!);
  url.pathname = `/${name}`;
  await migrateDatabase(url.toString());
  const connection = connectDatabase(url.toString());
  return {
    db: connection.db,
    async drop() {
      await connection.close();
      await admin.unsafe(`drop database ${name} with (force)`);
      await admin.end({ timeout: 5 });
    },
  };
}
