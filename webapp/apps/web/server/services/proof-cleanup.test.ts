// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { expect, test } from "bun:test";
import { SQLiteProofRepository } from "../repositories/sqlite-proof-repository";
import { PostgresProofRepository } from "../repositories/postgres-proof-repository";
import { LocalProofObjectStore } from "../storage/local-object-store";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { cleanupProofs } from "./proof-cleanup";
import { PROOF_RETENTION_MS, CLEANUP_BATCH_SIZE } from "./retention-policy";

// Run the same contract against an isolated Postgres database when supplied.
const postgresURL = process.env.HUSH_TEST_DATABASE_URL;
// CI provides PostgreSQL; never let the production backend's contract skip there.
if (process.env.CI && !postgresURL) throw new Error("HUSH_TEST_DATABASE_URL is required in CI");
for (const backend of postgresURL ? ["sqlite", "postgres"] : ["sqlite"]) {
  test(`${backend}: retention removes eligible data, preserves active proofs, retries storage failure`, async () => {
    const directory = await mkdtemp(join(tmpdir(), "hush-retention-"));
    const repository = backend === "postgres"
      ? new PostgresProofRepository(postgresURL!)
      : new SQLiteProofRepository(join(directory, "proofs.sqlite"));
    const objects = new LocalProofObjectStore(join(directory, "objects"), "http://hush.test");
    try {
      const now = new Date();
      const old = new Date(now.getTime() - PROOF_RETENTION_MS - 1000);
      const future = new Date(now.getTime() + PROOF_RETENTION_MS);
      const installation = await repository.createInstallation({
        publicKey: crypto.randomUUID(), fingerprint: crypto.randomUUID(),
        keyKind: "keychain", appVersion: "test", platformVersion: "test",
      });
      const create = async (expiresAt: Date, complete = true, createdAt = old) => {
        const id = crypto.randomUUID();
        const proof = await repository.createProof({
          id, slug: crypto.randomUUID(), installationId: installation.id,
          objectKey: `proofs/${id}.bin`, commitment: crypto.randomUUID(),
          ciphertextSha256: "test", ciphertextSize: 1, assuranceLevel: 2,
          completionTokenHash: "test", revocationSecretHash: "test", createdAt, expiresAt,
        });
        await objects.put(proof.objectKey, new Uint8Array([1]));
        if (complete) {
          await repository.completeProof({ id, receiptJson: "{}", receiptSignature: "test", completedAt: createdAt });
        }
        return proof;
      };
      const active = await create(future);
      const expired = await create(new Date(old.getTime() + 1));
      const revoked = await create(future);
      await repository.revokeProof(revoked.id, old);
      const pending = await create(future, false);
      const recentPending = await create(future, false, now);
      const recentExpired = await create(new Date(now.getTime() - 1000));
      const challenge = await repository.createChallenge({
        purpose: "enroll", nonce: crypto.randomUUID(), installationId: null,
        expiresAt: old,
      });
      expect((await cleanupProofs(repository, objects, now)).deleted).toBe(3);
      for (const proof of [expired, revoked, pending]) {
        expect(await repository.findProofById(proof.id)).toBeNull();
        expect(await objects.get(proof.objectKey)).toBeNull();
      }
      for (const proof of [active, recentPending, recentExpired]) {
        expect(await repository.findProofById(proof.id)).not.toBeNull();
        expect(await objects.get(proof.objectKey)).not.toBeNull();
      }
      expect(await repository.consumeChallenge({ id: challenge.id, purpose: "enroll", now: old })).toBeNull();

      const retry = await create(future, false);
      const remove = objects.delete.bind(objects);
      objects.delete = async () => { throw new Error("simulated storage outage"); };
      expect((await cleanupProofs(repository, objects, now)).failed).toBe(1);
      expect((await repository.findProofById(retry.id))?.deletedAt).not.toBeNull();
      expect(await repository.completeProof({ id: retry.id, receiptJson: "{}", receiptSignature: "test", completedAt: now })).toBeNull();
      objects.delete = remove;
      expect((await cleanupProofs(repository, objects, now)).deleted).toBe(1);
      expect(await repository.findProofById(retry.id)).toBeNull();
      expect(await objects.get(retry.objectKey)).toBeNull();

      // A concurrent completion wins only if it happens before the claim.
      const completed = await create(future, false);
      await repository.completeProof({ id: completed.id, receiptJson: "{}", receiptSignature: "test", completedAt: now });
      expect((await cleanupProofs(repository, objects, now)).deleted).toBe(0);
      expect(await objects.get(completed.objectKey)).not.toBeNull();

      for (let index = 0; index < CLEANUP_BATCH_SIZE + 1; index++) await create(future, false);
      expect((await cleanupProofs(repository, objects, now)).deleted).toBe(CLEANUP_BATCH_SIZE);
      expect((await cleanupProofs(repository, objects, now)).deleted).toBe(1);
    } finally {
      await repository.close();
      await rm(directory, { recursive: true, force: true });
    }
  });
}
