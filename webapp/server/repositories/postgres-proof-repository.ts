import { and, eq, gt, isNull } from "drizzle-orm";
import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import { challenges, installationKeys, proofAliases, proofs } from "../db/schema";
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
      .where(and(eq(proofs.id, input.id), isNull(proofs.completedAt)))
      .returning();
    return record ?? null;
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
