export type KeyKind = "secure_enclave" | "keychain" | "app_attest";
export type ChallengePurpose = "enroll" | "publish";
export type ProofStatus = "pending" | "valid" | "expired" | "revoked";

export type InstallationRecord = {
  id: string;
  publicKey: string;
  fingerprint: string;
  keyKind: KeyKind;
  appVersion: string;
  platformVersion: string;
  createdAt: Date;
  lastSeenAt: Date;
  revokedAt: Date | null;
};

export type ChallengeRecord = {
  id: string;
  purpose: ChallengePurpose;
  nonce: string;
  installationId: string | null;
  expiresAt: Date;
  consumedAt: Date | null;
  createdAt: Date;
};

export type ProofRecord = {
  id: string;
  slug: string;
  installationId: string;
  objectKey: string;
  commitment: string;
  ciphertextSha256: string;
  ciphertextSize: number;
  assuranceLevel: number;
  completionTokenHash: string;
  revocationSecretHash: string;
  receiptJson: string | null;
  receiptSignature: string | null;
  createdAt: Date;
  expiresAt: Date;
  completedAt: Date | null;
  revokedAt: Date | null;
  deletedAt: Date | null;
};

export type ProofAliasRecord = {
  code: string;
  proofId: string;
  createdAt: Date;
};
