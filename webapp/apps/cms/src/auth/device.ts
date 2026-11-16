// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The OAuth 2.0 Device Authorization Grant (RFC 8628), as `gh auth login`
// signs in: the CLI starts a sign-in and shows a short user code, the owner
// approves that code in the admin, and the CLI, polling with its secret device
// code, receives a new token once. Device codes are stored as hashes; every
// code expires after 15 minutes and is used at most once.
import { randomBytes, randomInt } from "node:crypto";
import { and, eq, gt, isNull } from "drizzle-orm";
import type { Database } from "../db/client";
import { deviceAuthorizations } from "../db/schema";
import { hashToken } from "./hash";
import { insertToken, tokenScopes } from "./tokens";

export const deviceCodeSeconds = 15 * 60;
/** The least time between two polls, in seconds (RFC 8628, section 3.5). */
export const pollSeconds = 5;
/** How long a token from a device sign-in works. */
export const deviceTokenDays = 90;
/** What every device token may do; going live still needs the owner's approval per post. */
export const deviceTokenScopes = tokenScopes;

// RFC 8628, section 6.1: consonants only, so no word or look-alike characters, 8 of 20 (~34 bits).
const userCodeAlphabet = "BCDFGHJKLMNPQRSTVWXZ";

/** "bcdf ghjk", "BCDFGHJK" and "BCDF-GHJK" are one code. */
export function normalizeUserCode(input: string) {
  const letters = input.toUpperCase().replace(/[^A-Z]/g, "");
  return letters.length === 8 ? `${letters.slice(0, 4)}-${letters.slice(4)}` : undefined;
}

export async function startDeviceAuthorization(db: Database, clientName: string) {
  const deviceCode = randomBytes(32).toString("base64url");
  const userCode = normalizeUserCode(Array.from({ length: 8 }, () => userCodeAlphabet[randomInt(userCodeAlphabet.length)]).join(""))!;
  await db.insert(deviceAuthorizations).values({
    deviceCodeHash: hashToken(deviceCode), userCode, clientName,
    expiresAt: new Date(Date.now() + deviceCodeSeconds * 1000),
  });
  return { deviceCode, userCode };
}

export type PollResult =
  | { token: string; actor: string; expiresAt: Date }
  | { error: "authorization_pending" | "slow_down" | "access_denied" | "expired_token" | "invalid_grant" };

/** One poll of the CLI. The row is locked, so two polls never both receive the token. */
export async function pollDeviceAuthorization(db: Database, deviceCode: string, now = new Date()): Promise<PollResult> {
  return db.transaction(async (tx) => {
    const [row] = await tx.select().from(deviceAuthorizations)
      .where(eq(deviceAuthorizations.deviceCodeHash, hashToken(deviceCode))).for("update");
    if (!row || row.tokenId) return { error: "invalid_grant" };
    if (row.expiresAt <= now) return { error: "expired_token" };
    if (row.deniedAt) return { error: "access_denied" };
    if (!row.approvedAt) {
      const tooSoon = row.lastPolledAt && now.getTime() - row.lastPolledAt.getTime() < pollSeconds * 1000;
      await tx.update(deviceAuthorizations).set({ lastPolledAt: now }).where(eq(deviceAuthorizations.id, row.id));
      return { error: tooSoon ? "slow_down" : "authorization_pending" };
    }
    const expiresAt = new Date(now.getTime() + deviceTokenDays * 86_400_000);
    const { token, id } = await insertToken(tx, { name: row.clientName, scopes: deviceTokenScopes, expiresAt });
    await tx.update(deviceAuthorizations).set({ tokenId: id }).where(eq(deviceAuthorizations.id, row.id));
    return { token, actor: `token:${row.clientName}`, expiresAt };
  });
}

/** A sign-in waiting for the owner's decision, by its user code; undefined once decided, used or expired. */
export async function pendingDeviceAuthorization(db: Database, userCode: string, now = new Date()) {
  const code = normalizeUserCode(userCode);
  if (!code) return undefined;
  const [row] = await db.select().from(deviceAuthorizations).where(eq(deviceAuthorizations.userCode, code));
  if (!row || row.approvedAt || row.deniedAt || row.tokenId || row.expiresAt <= now) return undefined;
  return { userCode: row.userCode, clientName: row.clientName, expiresAt: row.expiresAt, scopes: deviceTokenScopes, tokenDays: deviceTokenDays };
}

/** The owner's decision on a pending sign-in; false when there is none to decide. */
export async function decideDeviceAuthorization(db: Database, userCode: string, decision: "approve" | "deny", actor: string, now = new Date()) {
  const pending = await pendingDeviceAuthorization(db, userCode, now);
  if (!pending) return false;
  const updated = await db.update(deviceAuthorizations)
    .set(decision === "approve" ? { approvedAt: now, decidedBy: actor } : { deniedAt: now, decidedBy: actor })
    // Only while still undecided and unexpired: of two decisions at once, one wins.
    .where(and(
      eq(deviceAuthorizations.userCode, pending.userCode), isNull(deviceAuthorizations.approvedAt),
      isNull(deviceAuthorizations.deniedAt), gt(deviceAuthorizations.expiresAt, now),
    ))
    .returning({ id: deviceAuthorizations.id });
  return updated.length === 1;
}
