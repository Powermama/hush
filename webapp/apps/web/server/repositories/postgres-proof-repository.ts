import { and, eq, gt, isNull, isNotNull, lte, or, inArray, sql } from "drizzle-orm";
import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import { challenges, installationKeys, proofAliases, proofs } from "../db/schema";
import type {
  ChallengeRecord,
  InstallationRecord,
  ProofAliasRecord,
  ProofRecord,
} from "../domain/models";
import { PROOF_RETENTION_MS } from "../services/retention-policy";
import type {
  CreateInstallation,
  CreateProof,
  ProofRepository,
} from "./proof-repository";

export class PostgresProofRepository implements ProofRepository {
  private readonly client;
  private readonly db;

  constructor(connectionString: string) {
    this.client = postgres(connectionString, {
      max: 20,
      idle_timeout: 20,
      connect_timeout: 10,
      prepare: false,
    });
    this.db = drizzle(this.client);
  }

  async close(): Promise<void> {
    await this.client.end({ timeout: 5 });
  }

  async ping(): Promise<void> {
    await this.client`select 1`;
  }

  async createChallenge(
    input: Omit<ChallengeRecord, "id" | "consumedAt" | "createdAt">,
  ): Promise<ChallengeRecord> {
    const [record] = await this.db
      .insert(challenges)
      .values({
        ...input,
        id: Bun.randomUUIDv7(),
        consumedAt: null,
        createdAt: new Date(),
      })
      .returning();
    if (!record) throw new Error("Failed to create challenge");
    return record;
  }

  async consumeChallenge(input: {
    id: string;
    purpose: ChallengeRecord["purpose"];
    installationId?: string;
    now: Date;
  }): Promise<ChallengeRecord | null> {
    const clauses = [
      eq(challenges.id, input.id),
      eq(challenges.purpose, input.purpose),
      isNull(challenges.consumedAt),
      gt(challenges.expiresAt, input.now),
    ];
    if (input.installationId) {
      clauses.push(eq(challenges.installationId, input.installationId));
    }
    const [record] = await this.db
      .update(challenges)
      .set({ consumedAt: input.now })
      .where(and(...clauses))
      .returning();
    return record ?? null;
  }

  async createInstallation(
    input: CreateInstallation,
  ): Promise<InstallationRecord> {
    const now = new Date();
    const [record] = await this.db
      .insert(installationKeys)
      .values({
        id: Bun.randomUUIDv7(),
        publicKey: input.publicKey,
        fingerprint: input.fingerprint,
        kind: input.keyKind,
        appVersion: input.appVersion,
        platformVersion: input.platformVersion,
        createdAt: now,
        lastSeenAt: now,
      })
      .returning();
    if (!record) throw new Error("Failed to create installation");
    return { ...record, keyKind: record.kind };
  }

  async findInstallation(id: string): Promise<InstallationRecord | null> {
    const [record] = await this.db
      .select()
      .from(installationKeys)
      .where(eq(installationKeys.id, id))
      .limit(1);
    return record ? { ...record, keyKind: record.kind } : null;
  }

  async findInstallationByFingerprint(
    fingerprint: string,
  ): Promise<InstallationRecord | null> {
    const [record] = await this.db
      .select()
      .from(installationKeys)
      .where(eq(installationKeys.fingerprint, fingerprint))
      .limit(1);
    return record ? { ...record, keyKind: record.kind } : null;
  }

  async touchInstallation(id: string, now: Date): Promise<void> {
    await this.db
      .update(installationKeys)
      .set({ lastSeenAt: now })
      .where(eq(installationKeys.id, id));
  }

  async createProof(input: CreateProof): Promise<ProofRecord> {
    const [record] = await this.db
      .insert(proofs)
      .values(input)
      .returning();
    if (!record) throw new Error("Failed to create proof");
    return record;
  }

  async findProofById(id: string): Promise<ProofRecord | null> {
    const [record] = await this.db
      .select()
      .from(proofs)
      .where(eq(proofs.id, id))
      .limit(1);
    return record ?? null;
  }

  async findProofBySlug(slug: string): Promise<ProofRecord | null> {
    const [record] = await this.db
      .select()
      .from(proofs)
      .where(eq(proofs.slug, slug))
      .limit(1);
    return record ?? null;
  }

  async findProofByAlias(code: string): Promise<ProofRecord | null> {
    const [row] = await this.db
      .select({ proof: proofs })
      .from(proofAliases)
      .innerJoin(proofs, eq(proofAliases.proofId, proofs.id))
      .where(eq(proofAliases.code, code))
      .limit(1);
    return row?.proof ?? null;
  }

  async ensureProofAlias(
    input: ProofAliasRecord,
  ): Promise<ProofAliasRecord | null> {
    const [inserted] = await this.db
      .insert(proofAliases)
      .values(input)
      .onConflictDoNothing()
      .returning();
    if (inserted) return inserted;
    const [existing] = await this.db
      .select()
      .from(proofAliases)
      .where(eq(proofAliases.proofId, input.proofId))
      .limit(1);
    return existing ?? null;
  }

  async completeProof(input: {
    id: string;
    receiptJson: string;
    receiptSignature: string;
    completedAt: Date;
  }): Promise<ProofRecord | null> {
    const [record] = await this.db
      .update(proofs)
      .set(input)
      .where(and(
          eq(proofs.id, input.id), isNull(proofs.completedAt),
          isNull(proofs.revokedAt), isNull(proofs.deletedAt),
          gt(proofs.expiresAt, input.completedAt),
        ))
      .returning();
    return record ?? null;
  }


  // Claim before object I/O so an abandoned reservation cannot complete while
  // its bytes are being removed. Failed deletions remain claimed for retry.
  async claimProofsForDeletion(now: Date, limit: number): Promise<ProofRecord[]> {
    const cutoff = new Date(now.getTime() - PROOF_RETENTION_MS);
    const eligible = or(
      isNotNull(proofs.deletedAt),
      lte(proofs.expiresAt, cutoff),
      lte(proofs.revokedAt, cutoff),
      and(isNull(proofs.completedAt), lte(proofs.createdAt, cutoff)),
    );
    const candidates = await this.db.select({ id: proofs.id })
      .from(proofs).where(eligible)
      .orderBy(sql`coalesce(${proofs.deletedAt}, ${proofs.createdAt})`, proofs.id)
      .limit(limit);
    if (!candidates.length) return [];
    return await this.db.update(proofs).set({ deletedAt: now })
      .where(and(inArray(proofs.id, candidates.map((row) => row.id)), eligible))
      .returning();
  }

  async deleteClaimedProof(id: string): Promise<void> {
    await this.db.delete(proofs)
      .where(and(eq(proofs.id, id), isNotNull(proofs.deletedAt)));
  }

  async deleteExpiredChallenges(now: Date, limit: number): Promise<number> {
    const candidates = await this.db.select({ id: challenges.id })
      .from(challenges).where(lte(challenges.expiresAt, now))
      .orderBy(challenges.expiresAt).limit(limit);
    if (!candidates.length) return 0;
    const removed = await this.db.delete(challenges)
      .where(inArray(challenges.id, candidates.map((row) => row.id)))
      .returning({ id: challenges.id });
    return removed.length;
  }

  async revokeProof(id: string, revokedAt: Date): Promise<ProofRecord | null> {
    const [updated] = await this.db
      .update(proofs)
      .set({ revokedAt })
      .where(and(eq(proofs.id, id), isNull(proofs.revokedAt)))
      .returning();
    return updated ?? this.findProofById(id);
  }
}
