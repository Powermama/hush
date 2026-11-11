import { Database } from "bun:sqlite";
import { and, eq, gt, isNull } from "drizzle-orm";
import { drizzle } from "drizzle-orm/bun-sqlite";
import {
  sqliteChallenges,
  sqliteInstallationKeys,
  sqliteProofAliases,
  sqliteProofs,
} from "../db/sqlite-schema";
import type {
  ChallengeRecord,
  InstallationRecord,
  ProofAliasRecord,
  ProofRecord,
} from "../domain/models";
import type {
  CreateInstallation,
  CreateProof,
  ProofRepository,
} from "./proof-repository";

export class SQLiteProofRepository implements ProofRepository {
  private readonly sqlite: Database;
  private readonly db;

  constructor(path = ":memory:") {
    this.sqlite = new Database(path, { create: true });
    this.sqlite.exec("PRAGMA foreign_keys = ON");
    this.db = drizzle(this.sqlite);
    this.migrate();
  }

  close(): void {
    this.sqlite.close();
  }

  async createChallenge(
    input: Omit<ChallengeRecord, "id" | "consumedAt" | "createdAt">,
  ): Promise<ChallengeRecord> {
    const record: ChallengeRecord = {
      ...input,
      id: Bun.randomUUIDv7(),
      consumedAt: null,
      createdAt: new Date(),
    };
    this.db.insert(sqliteChallenges).values(record).run();
    return record;
  }

  async consumeChallenge(input: {
    id: string;
    purpose: ChallengeRecord["purpose"];
    installationId?: string;
    now: Date;
  }): Promise<ChallengeRecord | null> {
    const clauses = [
      eq(sqliteChallenges.id, input.id),
      eq(sqliteChallenges.purpose, input.purpose),
      isNull(sqliteChallenges.consumedAt),
      gt(sqliteChallenges.expiresAt, input.now),
    ];
    if (input.installationId) {
      clauses.push(eq(sqliteChallenges.installationId, input.installationId));
    }
    const rows = this.db
      .update(sqliteChallenges)
      .set({ consumedAt: input.now })
      .where(and(...clauses))
      .returning()
      .all();
    return rows[0] ?? null;
  }

  async createInstallation(
    input: CreateInstallation,
  ): Promise<InstallationRecord> {
    const now = new Date();
    const record: InstallationRecord = {
      ...input,
      id: Bun.randomUUIDv7(),
      createdAt: now,
      lastSeenAt: now,
      revokedAt: null,
    };
    this.db.insert(sqliteInstallationKeys).values({ ...record, kind: input.keyKind }).run();
    return record;
  }

  async findInstallation(id: string): Promise<InstallationRecord | null> {
    const row = this.db
      .select()
      .from(sqliteInstallationKeys)
      .where(eq(sqliteInstallationKeys.id, id))
      .get();
    if (!row) return null;
    return { ...row, keyKind: row.kind };
  }

  async findInstallationByFingerprint(
    fingerprint: string,
  ): Promise<InstallationRecord | null> {
    const row = this.db
      .select()
      .from(sqliteInstallationKeys)
      .where(eq(sqliteInstallationKeys.fingerprint, fingerprint))
      .get();
    return row ? { ...row, keyKind: row.kind } : null;
  }

  async touchInstallation(id: string, now: Date): Promise<void> {
    this.db
      .update(sqliteInstallationKeys)
      .set({ lastSeenAt: now })
      .where(eq(sqliteInstallationKeys.id, id))
      .run();
  }

  async createProof(input: CreateProof): Promise<ProofRecord> {
    const record: ProofRecord = {
      ...input,
      receiptJson: null,
      receiptSignature: null,
      completedAt: null,
      revokedAt: null,
      deletedAt: null,
    };
    this.db.insert(sqliteProofs).values(record).run();
    return record;
  }

  async findProofById(id: string): Promise<ProofRecord | null> {
    return (
      this.db.select().from(sqliteProofs).where(eq(sqliteProofs.id, id)).get() ??
      null
    );
  }

  async findProofBySlug(slug: string): Promise<ProofRecord | null> {
    return (
      this.db
        .select()
        .from(sqliteProofs)
        .where(eq(sqliteProofs.slug, slug))
        .get() ?? null
    );
  }

  async findProofByAlias(code: string): Promise<ProofRecord | null> {
    const row = this.db
      .select({ proof: sqliteProofs })
      .from(sqliteProofAliases)
      .innerJoin(sqliteProofs, eq(sqliteProofAliases.proofId, sqliteProofs.id))
      .where(eq(sqliteProofAliases.code, code))
      .get();
    return row?.proof ?? null;
  }

  async ensureProofAlias(
    input: ProofAliasRecord,
  ): Promise<ProofAliasRecord | null> {
    const inserted = this.db
      .insert(sqliteProofAliases)
      .values(input)
      .onConflictDoNothing()
      .returning()
      .get();
    if (inserted) return inserted;
    return (
      this.db
        .select()
        .from(sqliteProofAliases)
        .where(eq(sqliteProofAliases.proofId, input.proofId))
        .get() ?? null
    );
  }

  async completeProof(input: {
    id: string;
    receiptJson: string;
    receiptSignature: string;
    completedAt: Date;
  }): Promise<ProofRecord | null> {
    return (
      this.db
        .update(sqliteProofs)
        .set(input)
        .where(and(eq(sqliteProofs.id, input.id), isNull(sqliteProofs.completedAt)))
        .returning()
        .get() ?? null
    );
  }

  async revokeProof(id: string, revokedAt: Date): Promise<ProofRecord | null> {
    return (
      this.db
        .update(sqliteProofs)
        .set({ revokedAt })
        .where(and(eq(sqliteProofs.id, id), isNull(sqliteProofs.revokedAt)))
        .returning()
        .get() ?? this.findProofById(id)
    );
  }

  private migrate(): void {
    this.sqlite.exec(`
      BEGIN IMMEDIATE;
      CREATE TABLE IF NOT EXISTS installation_keys (
        id TEXT PRIMARY KEY,
        public_key TEXT NOT NULL UNIQUE,
        fingerprint TEXT NOT NULL UNIQUE,
        key_kind TEXT NOT NULL CHECK (key_kind IN ('secure_enclave','keychain','app_attest')),
        app_version TEXT NOT NULL,
        platform_version TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        last_seen_at INTEGER NOT NULL,
        revoked_at INTEGER
      );
      CREATE TABLE IF NOT EXISTS challenges (
        id TEXT PRIMARY KEY,
        purpose TEXT NOT NULL CHECK (purpose IN ('enroll','publish')),
        nonce TEXT NOT NULL UNIQUE,
        installation_key_id TEXT REFERENCES installation_keys(id) ON DELETE CASCADE,
        expires_at INTEGER NOT NULL,
        consumed_at INTEGER,
        created_at INTEGER NOT NULL
      );
      CREATE INDEX IF NOT EXISTS challenges_expiry_idx ON challenges(expires_at);
      CREATE TABLE IF NOT EXISTS proofs (
        id TEXT PRIMARY KEY,
        slug TEXT NOT NULL UNIQUE,
        installation_key_id TEXT NOT NULL REFERENCES installation_keys(id) ON DELETE RESTRICT,
        object_key TEXT NOT NULL UNIQUE,
        inner_commitment TEXT NOT NULL UNIQUE,
        ciphertext_sha256 TEXT NOT NULL,
        ciphertext_size INTEGER NOT NULL CHECK (ciphertext_size > 0 AND ciphertext_size <= 8000000),
        assurance_level INTEGER NOT NULL CHECK (assurance_level BETWEEN 1 AND 4),
        completion_token_hash TEXT NOT NULL,
        revocation_secret_hash TEXT NOT NULL,
        receipt_json TEXT,
        receipt_signature TEXT,
        receipt_version INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL,
        completed_at INTEGER,
        revoked_at INTEGER,
        deleted_at INTEGER
      );
      CREATE INDEX IF NOT EXISTS proofs_installation_idx ON proofs(installation_key_id);
      CREATE INDEX IF NOT EXISTS proofs_expiry_idx ON proofs(expires_at);
      CREATE TABLE IF NOT EXISTS proof_aliases (
        code TEXT PRIMARY KEY,
        proof_id TEXT NOT NULL UNIQUE REFERENCES proofs(id) ON DELETE CASCADE,
        created_at INTEGER NOT NULL
      );
      COMMIT;
    `);

    const storageVersion = this.sqlite.query("PRAGMA user_version").get() as
      | { user_version: number }
      | null;
    if ((storageVersion?.user_version ?? 0) >= 1) return;

    const secondsStorageUpperBound = 100_000_000_000;
    this.sqlite.exec(`
      BEGIN IMMEDIATE;
      UPDATE installation_keys SET created_at = created_at * 1000 WHERE created_at < ${secondsStorageUpperBound};
      UPDATE installation_keys SET last_seen_at = last_seen_at * 1000 WHERE last_seen_at < ${secondsStorageUpperBound};
      UPDATE installation_keys SET revoked_at = revoked_at * 1000 WHERE revoked_at IS NOT NULL AND revoked_at < ${secondsStorageUpperBound};
      UPDATE challenges SET expires_at = expires_at * 1000 WHERE expires_at < ${secondsStorageUpperBound};
      UPDATE challenges SET consumed_at = consumed_at * 1000 WHERE consumed_at IS NOT NULL AND consumed_at < ${secondsStorageUpperBound};
      UPDATE challenges SET created_at = created_at * 1000 WHERE created_at < ${secondsStorageUpperBound};
      UPDATE proofs SET created_at = created_at * 1000 WHERE created_at < ${secondsStorageUpperBound};
      UPDATE proofs SET expires_at = expires_at * 1000 WHERE expires_at < ${secondsStorageUpperBound};
      UPDATE proofs SET completed_at = completed_at * 1000 WHERE completed_at IS NOT NULL AND completed_at < ${secondsStorageUpperBound};
      UPDATE proofs SET revoked_at = revoked_at * 1000 WHERE revoked_at IS NOT NULL AND revoked_at < ${secondsStorageUpperBound};
      UPDATE proofs SET deleted_at = deleted_at * 1000 WHERE deleted_at IS NOT NULL AND deleted_at < ${secondsStorageUpperBound};
      PRAGMA user_version = 1;
      COMMIT;
    `);
  }
}
