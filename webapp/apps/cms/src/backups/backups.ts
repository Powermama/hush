// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Database backups with the official PostgreSQL tools: pg_dump writes a
// custom-format archive to the backup store, pg_restore reads it back. The
// connection travels in PG* environment variables, never in the process
// arguments, so the password does not show up in process listings.
import type { ObjectStore } from "../storage/object-store";

const prefix = "cms/";
const dayMs = 86_400_000;

/** libpq's standard variables for a postgresql:// URL. */
function connection(url: string): Record<string, string> {
  const parsed = new URL(url);
  return {
    PGHOST: parsed.hostname,
    PGPORT: parsed.port || "5432",
    PGUSER: decodeURIComponent(parsed.username),
    PGPASSWORD: decodeURIComponent(parsed.password),
    PGDATABASE: parsed.pathname.slice(1),
  };
}

async function run(command: string[], databaseUrl: string, input?: Uint8Array) {
  const process = Bun.spawn(command, {
    env: { PATH: Bun.env.PATH ?? "/usr/bin:/bin", ...connection(databaseUrl) },
    stdin: input ?? "ignore", stdout: "pipe", stderr: "pipe",
  });
  const [output, errors, code] = await Promise.all([
    new Response(process.stdout).bytes(), new Response(process.stderr).text(), process.exited,
  ]);
  if (code !== 0) throw new Error(`${command[0]} failed (${code}): ${errors.trim()}`);
  return output;
}

/** The time a backup was taken, read from its key. */
export function backupTime(key: string) {
  const stamp = /^cms\/(\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}-\d{3}Z)\.dump$/.exec(key)?.[1];
  if (!stamp) return undefined;
  const [date, time] = stamp.split("T");
  const [hours, minutes, seconds, millis] = time!.replace("Z", "").split("-");
  return new Date(`${date}T${hours}:${minutes}:${seconds}.${millis}Z`);
}

/** Backups, newest first. */
export async function listBackups(store: ObjectStore) {
  const keys = (await store.list(prefix)).filter((key) => backupTime(key));
  return keys.sort((a, b) => backupTime(b)!.getTime() - backupTime(a)!.getTime());
}

/** Removes backups older than keepDays, always keeping the newest. */
export async function pruneBackups(store: ObjectStore, keepDays: number, now = new Date()) {
  const [, ...older] = await listBackups(store);
  const expired = older.filter((key) => now.getTime() - backupTime(key)!.getTime() > keepDays * dayMs);
  for (const key of expired) await store.delete(key);
  return expired;
}

export async function backupDatabase(databaseUrl: string, store: ObjectStore, keepDays: number, now = new Date()) {
  const archive = await run(["pg_dump", "--format=custom", "--no-owner", "--no-privileges"], databaseUrl);
  const key = `${prefix}${now.toISOString().replace(/[:.]/g, "-")}.dump`;
  await store.put(key, archive, "application/octet-stream");
  return { key, bytes: archive.byteLength, removed: await pruneBackups(store, keepDays, now) };
}

/** Replaces the target database's contents with the backup. */
export async function restoreDatabase(store: ObjectStore, key: string, targetUrl: string) {
  const archive = await store.get(key);
  if (!archive) throw new Error(`No backup ${key}`);
  // pg_restore without --dbname only prints SQL; the name carries no secret.
  const database = new URL(targetUrl).pathname.slice(1);
  await run(["pg_restore", "--clean", "--if-exists", "--no-owner", "--no-privileges", "--exit-on-error", "--single-transaction", `--dbname=${database}`], targetUrl, archive);
}
