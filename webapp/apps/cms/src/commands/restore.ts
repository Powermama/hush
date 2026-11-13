// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Restores a backup into a database:
//   bun run cms:restore --target-url postgresql://... [--key cms/<time>.dump]
// The newest backup is used unless --key names one. Restoring over the live
// database needs --overwrite-live, so a drill can never replace it by accident.
import { parseArgs } from "node:util";
import { listBackups, restoreDatabase } from "../backups/backups";
import { loadConfig } from "../config";
import { createObjectStore } from "../storage/object-store";

const { values } = parseArgs({ options: { "target-url": { type: "string" }, key: { type: "string" }, "overwrite-live": { type: "boolean" } } });
const config = loadConfig();
const target = values["target-url"];
if (!target) {
  console.error("Usage: --target-url <postgresql://...> [--key cms/<time>.dump] [--overwrite-live]");
  process.exit(1);
}
if (target === config.databaseUrl && !values["overwrite-live"]) {
  console.error("The target is the live CMS database; pass --overwrite-live to replace it.");
  process.exit(1);
}
const store = createObjectStore(config.backups);
const key = values.key ?? (await listBackups(store))[0];
if (!key) {
  console.error("There is no backup to restore.");
  process.exit(1);
}
await restoreDatabase(store, key, target);
console.info(JSON.stringify({ level: "info", message: "Restored a CMS backup", key }));
