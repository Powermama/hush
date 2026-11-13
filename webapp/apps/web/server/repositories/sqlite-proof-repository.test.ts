import { Database } from "bun:sqlite";
import { expect, test } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { SQLiteProofRepository } from "./sqlite-proof-repository";

test("upgrades local timestamp storage to milliseconds exactly once", async () => {
  const directory = mkdtempSync(join(tmpdir(), "hush-sqlite-migration-"));
  const path = join(directory, "hush.sqlite");

  try {
    const initial = new SQLiteProofRepository(path);
    const installation = await initial.createInstallation({
      publicKey: "migration-public-key",
      fingerprint: "migration-fingerprint",
      keyKind: "keychain",
      appVersion: "test",
      platformVersion: "test",
    });
    initial.close();

    const legacy = new Database(path);
    const seconds = Math.floor(installation.createdAt.getTime() / 1000);
    legacy
      .query("UPDATE installation_keys SET created_at = ?, last_seen_at = ? WHERE id = ?")
      .run(seconds, seconds, installation.id);
    legacy.exec("PRAGMA user_version = 0");
    legacy.close();

    const migrated = new SQLiteProofRepository(path);
    expect((await migrated.findInstallation(installation.id))?.createdAt.getTime()).toBe(
      seconds * 1000,
    );
    migrated.close();

    const reopened = new SQLiteProofRepository(path);
    expect((await reopened.findInstallation(installation.id))?.createdAt.getTime()).toBe(
      seconds * 1000,
    );
    reopened.close();
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("keeps aliases immutable and detects a short-code collision", async () => {
  const repository = new SQLiteProofRepository();
  try {
    const installation = await repository.createInstallation({
      publicKey: "alias-public-key",
      fingerprint: "alias-fingerprint",
      keyKind: "keychain",
      appVersion: "test",
      platformVersion: "test",
    });
    const now = new Date();
    const first = await repository.createProof({
      id: Bun.randomUUIDv7(),
      slug: "canonical-proof-slug-one",
      installationId: installation.id,
      objectKey: "proofs/one.bin",
      commitment: "commitment-one",
      ciphertextSha256: "ciphertext-one",
      ciphertextSize: 128,
      assuranceLevel: 2,
      completionTokenHash: "completion-one",
      revocationSecretHash: "revocation-one",
      createdAt: now,
      expiresAt: new Date(now.getTime() + 60_000),
    });
    const second = await repository.createProof({
      id: Bun.randomUUIDv7(),
      slug: "canonical-proof-slug-two",
      installationId: installation.id,
      objectKey: "proofs/two.bin",
      commitment: "commitment-two",
      ciphertextSha256: "ciphertext-two",
      ciphertextSize: 128,
      assuranceLevel: 2,
      completionTokenHash: "completion-two",
      revocationSecretHash: "revocation-two",
      createdAt: now,
      expiresAt: new Date(now.getTime() + 60_000),
    });

    const firstAlias = await repository.ensureProofAlias({
      code: "Ab3dE7",
      proofId: first.id,
      createdAt: now,
    });
    expect(firstAlias?.code).toBe("Ab3dE7");
    expect(
      await repository.ensureProofAlias({
        code: "Ab3dE7",
        proofId: second.id,
        createdAt: now,
      }),
    ).toBeNull();
    expect(
      (
        await repository.ensureProofAlias({
          code: "Lm4nR8",
          proofId: second.id,
          createdAt: now,
        })
      )?.code,
    ).toBe("Lm4nR8");
    expect(
      (
        await repository.ensureProofAlias({
          code: "Zz9yY8",
          proofId: first.id,
          createdAt: now,
        })
      )?.code,
    ).toBe("Ab3dE7");
  } finally {
    repository.close();
  }
});
