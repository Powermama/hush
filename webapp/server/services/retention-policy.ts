// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann

// A short terminal-state window explains expired/revoked links and outlives
// five-minute presigned uploads. No message is accessible during this window.
export const PROOF_RETENTION_MS = 24 * 60 * 60 * 1000;
export const CLEANUP_INTERVAL_MS = 60_000;
export const CLEANUP_BATCH_SIZE = 100;
