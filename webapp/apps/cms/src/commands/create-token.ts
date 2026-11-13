// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Creates an API token and prints it once. Run inside the CMS container:
//   bun run cms:token --name hush-seo --scopes posts:read,posts:write [--days 90]
import { parseArgs } from "node:util";
import { createToken, tokenScopes, type TokenScope } from "../auth/tokens";
import { connectDatabase } from "../db/client";
import { loadConfig } from "../config";

const { values } = parseArgs({ options: { name: { type: "string" }, scopes: { type: "string" }, days: { type: "string" } } });
const scopes = (values.scopes ?? "").split(",").filter(Boolean);
const unknown = scopes.filter((scope) => !tokenScopes.includes(scope as TokenScope));
if (!values.name || !scopes.length || unknown.length) {
  console.error(`Usage: --name <name> --scopes ${tokenScopes.join(",")} [--days <n>]${unknown.length ? `\nUnknown scopes: ${unknown.join(", ")}` : ""}`);
  process.exit(1);
}
const expiresAt = values.days ? new Date(Date.now() + Number(values.days) * 86_400_000) : undefined;
const { db, close } = connectDatabase(loadConfig().databaseUrl);
try {
  console.info(await createToken(db, { name: values.name, scopes: scopes as TokenScope[], expiresAt }));
} finally {
  await close();
}
