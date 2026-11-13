// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { defineConfig } from "drizzle-kit";

export default defineConfig({
  dialect: "postgresql",
  schema: "./src/db/schema.ts",
  out: "./src/db/migrations",
  dbCredentials: {
    url: process.env.CMS_DATABASE_URL ?? "postgres://cms:cms@127.0.0.1:5432/cms",
  },
  strict: true,
  verbose: true,
});
