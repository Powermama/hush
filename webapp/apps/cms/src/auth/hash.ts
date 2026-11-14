// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { createHash } from "node:crypto";

/** Secrets (API tokens, session tokens) are stored only as this hash. */
export const hashToken = (token: string) => createHash("sha256").update(token).digest("hex");
