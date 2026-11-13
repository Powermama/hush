// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// CMS-BACKUP-002: backups are named by time, listed newest first and kept for
// the configured days, always keeping the newest. scripts/backup-drill.sh
// restores a real backup (CMS-BACKUP-001).
import { expect, test } from "bun:test";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { backupTime, listBackups, pruneBackups } from "../src/backups/backups";
import { LocalObjectStore } from "../src/storage/object-store";

const keyAt = (date: Date) => `cms/${date.toISOString().replace(/[:.]/g, "-")}.dump`;

test("reads the backup time from its key", () => {
  const taken = new Date("2026-11-13T03:04:05.678Z");
  expect(backupTime(keyAt(taken))?.toISOString()).toBe(taken.toISOString());
  expect(backupTime("cms/notes.txt")).toBeUndefined();
});

test("CMS-BACKUP-002 keeps recent backups and always the newest", async () => {
  const store = new LocalObjectStore(await mkdtemp(join(tmpdir(), "hush-cms-backups-")));
  const now = new Date("2026-12-31T00:00:00.000Z");
  const daysAgo = (days: number) => new Date(now.getTime() - days * 86_400_000);
  for (const days of [1, 10, 31, 45]) await store.put(keyAt(daysAgo(days)), new Uint8Array([days]), "application/octet-stream");
  await store.put("cms/unrelated.txt", new Uint8Array([0]), "text/plain");

  expect(await listBackups(store)).toEqual([keyAt(daysAgo(1)), keyAt(daysAgo(10)), keyAt(daysAgo(31)), keyAt(daysAgo(45))]);
  expect((await pruneBackups(store, 30, now)).sort()).toEqual([keyAt(daysAgo(31)), keyAt(daysAgo(45))].sort());
  expect(await listBackups(store)).toEqual([keyAt(daysAgo(1)), keyAt(daysAgo(10))]);

  // A lone old backup is the only copy left, so it stays.
  const lone = new LocalObjectStore(await mkdtemp(join(tmpdir(), "hush-cms-backups-")));
  await lone.put(keyAt(daysAgo(90)), new Uint8Array([9]), "application/octet-stream");
  expect(await pruneBackups(lone, 30, now)).toEqual([]);
});
