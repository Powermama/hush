// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Backs up the CMS database once: bun run cms:backup
import { backupDatabase } from "../backups/backups";
import { loadConfig } from "../config";
import { createObjectStore } from "../storage/object-store";

const config = loadConfig();
const result = await backupDatabase(config.databaseUrl, createObjectStore(config.backups), config.backups.keepDays);
console.info(JSON.stringify({ level: "info", message: "Backed up the CMS database", ...result }));
