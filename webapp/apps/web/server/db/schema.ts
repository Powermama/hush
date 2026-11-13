import {
  bigint,
  index,
  integer,
  pgEnum,
  pgTable,
  smallint,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from "drizzle-orm/pg-core";

export const keyKind = pgEnum("key_kind", [
  "secure_enclave",
  "keychain",
  "app_attest",
]);
export const challengePurpose = pgEnum("challenge_purpose", [
  "enroll",
  "publish",
]);

export const installationKeys = pgTable(
  "installation_keys",
  {
    id: uuid("id").primaryKey(),
    publicKey: text("public_key").notNull(),
    fingerprint: text("fingerprint").notNull(),
    kind: keyKind("key_kind").notNull(),
    appVersion: text("app_version").notNull(),
    platformVersion: text("platform_version").notNull(),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull(),
    lastSeenAt: timestamp("last_seen_at", { withTimezone: true }).notNull(),
    revokedAt: timestamp("revoked_at", { withTimezone: true }),
  },
  (table) => [
    uniqueIndex("installation_keys_public_key_uq").on(table.publicKey),
    uniqueIndex("installation_keys_fingerprint_uq").on(table.fingerprint),
  ],
);

export const challenges = pgTable(
  "challenges",
  {
    id: uuid("id").primaryKey(),
    purpose: challengePurpose("purpose").notNull(),
    nonce: text("nonce").notNull(),
    installationId: uuid("installation_key_id").references(
      () => installationKeys.id,
      { onDelete: "cascade" },
    ),
    expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
    consumedAt: timestamp("consumed_at", { withTimezone: true }),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull(),
  },
  (table) => [
    uniqueIndex("challenges_nonce_uq").on(table.nonce),
    index("challenges_expiry_idx").on(table.expiresAt),
    index("challenges_installation_idx").on(table.installationId),
  ],
);

export const proofs = pgTable(
  "proofs",
  {
    id: uuid("id").primaryKey(),
    slug: text("slug").notNull(),
    installationId: uuid("installation_key_id")
      .notNull()
      .references(() => installationKeys.id, { onDelete: "restrict" }),
    objectKey: text("object_key").notNull(),
    commitment: text("inner_commitment").notNull(),
    ciphertextSha256: text("ciphertext_sha256").notNull(),
    ciphertextSize: bigint("ciphertext_size", { mode: "number" }).notNull(),
    assuranceLevel: smallint("assurance_level").notNull(),
    completionTokenHash: text("completion_token_hash").notNull(),
    revocationSecretHash: text("revocation_secret_hash").notNull(),
    receiptJson: text("receipt_json"),
    receiptSignature: text("receipt_signature"),
    receiptVersion: integer("receipt_version").notNull().default(1),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull(),
    expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
    completedAt: timestamp("completed_at", { withTimezone: true }),
    revokedAt: timestamp("revoked_at", { withTimezone: true }),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
  },
  (table) => [
    uniqueIndex("proofs_slug_uq").on(table.slug),
    uniqueIndex("proofs_object_key_uq").on(table.objectKey),
    uniqueIndex("proofs_commitment_uq").on(table.commitment),
    index("proofs_installation_idx").on(table.installationId),
    index("proofs_expiry_idx").on(table.expiresAt),
  ],
);

export const proofAliases = pgTable(
  "proof_aliases",
  {
    code: text("code").primaryKey(),
    proofId: uuid("proof_id")
      .notNull()
      .references(() => proofs.id, { onDelete: "cascade" }),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull(),
  },
  (table) => [uniqueIndex("proof_aliases_proof_id_uq").on(table.proofId)],
);
