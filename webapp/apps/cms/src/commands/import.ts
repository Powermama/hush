// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Imports Markdown articles: bun run cms:import <content-dir>
import { loadConfig } from "../config";
import { connectDatabase } from "../db/client";
import { createObjectStore } from "../storage/object-store";
import { importArticles } from "../posts/import";

const contentDir = process.argv[2];
if (!contentDir) {
  console.error("Usage: bun run cms:import <content-dir with en/ and de/>");
  process.exit(1);
}
const config = loadConfig();
const { db, close } = connectDatabase(config.databaseUrl);
try {
  const report = await importArticles({ db, media: createObjectStore(config.media) }, contentDir);
  console.info(JSON.stringify(report, null, 2));
  if (report.failed.length) process.exitCode = 1;
} finally {
  await close();
}
