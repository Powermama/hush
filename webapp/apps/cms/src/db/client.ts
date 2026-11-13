// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import * as schema from "./schema";

export function connectDatabase(url: string) {
  const client = postgres(url, { max: 10 });
  return { db: drizzle(client, { schema }), close: () => client.end({ timeout: 5 }) };
}

export type Database = ReturnType<typeof connectDatabase>["db"];
