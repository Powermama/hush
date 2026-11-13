// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { createApp } from "./app";
import type { Database } from "./db/client";

// The document only describes routes; no database is touched.
const document = createApp(undefined as unknown as Database).getOpenAPI31Document({ openapi: "3.1.0", info: { title: "hush CMS", version: "1.0.0" } });
await Bun.write(new URL("../openapi/hush-cms.json", import.meta.url), `${JSON.stringify(document, null, 2)}\n`);
