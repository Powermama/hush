// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import type { ProofRepository } from "../repositories/proof-repository";
import type { ProofObjectStore } from "../storage/proof-object-store";
import { CLEANUP_BATCH_SIZE, CLEANUP_INTERVAL_MS } from "./retention-policy";

export async function cleanupProofs(
  repository: ProofRepository,
  objects: ProofObjectStore,
  now = new Date(),
) {
  const challenges = await repository.deleteExpiredChallenges(now, CLEANUP_BATCH_SIZE);
  const proofs = await repository.claimProofsForDeletion(now, CLEANUP_BATCH_SIZE);
  let deleted = 0;
  let failed = 0;
  // Each storage operation has a bounded timeout. Keep concurrency low so
  // cleanup cannot saturate the request path or the database pool.
  for (let offset = 0; offset < proofs.length; offset += 4) {
    await Promise.all(proofs.slice(offset, offset + 4).map(async (proof) => {
      try {
        await objects.delete(proof.objectKey);
        await repository.deleteClaimedProof(proof.id);
        deleted += 1;
      } catch {
        // Keep the claimed record, including its object key, for the next pass.
        // Do not log private proof identifiers, links or storage errors.
        failed += 1;
      }
    }));
  }
  return { challenges, deleted, failed };
}

export function startProofCleanup(repository: ProofRepository, objects: ProofObjectStore) {
  let running: Promise<void> | undefined;
  const run = () => {
    if (running) return;
    running = cleanupProofs(repository, objects)
      .then((result) => {
        if (result.challenges || result.deleted || result.failed) {
          console.info(JSON.stringify({ message: "Proof retention cleanup", ...result }));
        }
      })
      .catch(() => console.error(JSON.stringify({ message: "Proof retention cleanup failed; will retry" })))
      .finally(() => { running = undefined; });
  };
  const timer = setInterval(run, CLEANUP_INTERVAL_MS);
  timer.unref();
  run();
  return {
    async stop() {
      clearInterval(timer);
      await running;
    },
  };
}
