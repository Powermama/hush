import type {
  ChallengePurpose,
  ChallengeRecord,
  InstallationRecord,
  KeyKind,
  ProofAliasRecord,
  ProofRecord,
} from "../domain/models";

export type CreateInstallation = {
  publicKey: string;
  fingerprint: string;
  keyKind: KeyKind;
  appVersion: string;
  platformVersion: string;
};

export type CreateProof = Omit<
  ProofRecord,
  "receiptJson" | "receiptSignature" | "completedAt" | "revokedAt" | "deletedAt"
>;

export interface ProofRepository {
  createChallenge(input: {
    purpose: ChallengePurpose;
    nonce: string;
    installationId: string | null;
    expiresAt: Date;
  }): Promise<ChallengeRecord>;
  consumeChallenge(input: {
    id: string;
    purpose: ChallengePurpose;
    installationId?: string;
    now: Date;
  }): Promise<ChallengeRecord | null>;
  createInstallation(input: CreateInstallation): Promise<InstallationRecord>;
  findInstallation(id: string): Promise<InstallationRecord | null>;
  findInstallationByFingerprint(fingerprint: string): Promise<InstallationRecord | null>;
  touchInstallation(id: string, now: Date): Promise<void>;
  createProof(input: CreateProof): Promise<ProofRecord>;
  findProofById(id: string): Promise<ProofRecord | null>;
  findProofBySlug(slug: string): Promise<ProofRecord | null>;
  findProofByAlias(code: string): Promise<ProofRecord | null>;
  ensureProofAlias(input: ProofAliasRecord): Promise<ProofAliasRecord | null>;
  completeProof(input: {
    id: string;
    receiptJson: string;
    receiptSignature: string;
    completedAt: Date;
  }): Promise<ProofRecord | null>;
  claimProofsForDeletion(now: Date, limit: number): Promise<ProofRecord[]>;
  deleteClaimedProof(id: string): Promise<void>;
  deleteExpiredChallenges(now: Date, limit: number): Promise<number>;
  revokeProof(id: string, revokedAt: Date): Promise<ProofRecord | null>;
}
