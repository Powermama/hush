// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Run every minute by a Coolify Scheduled Task: bun run cms:publish-due
import { connectDatabase } from "../db/client";
import { loadConfig } from "../config";
import { publishDuePosts } from "../posts/service";

const { db, close } = connectDatabase(loadConfig().databaseUrl);
try {
  const published = await publishDuePosts(db);
  console.info(JSON.stringify({ level: "info", message: "Published due posts", count: published.length, slugs: published.map((post) => `${post.lang}/${post.slug}`) }));
} finally {
  await close();
}
