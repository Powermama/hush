import { integer, sqliteTable, text, uniqueIndex } from "drizzle-orm/sqlite-core";

export const sqliteInstallationKeys = sqliteTable(
  "installation_keys",
  {
    id: text("id").primaryKey(),
    publicKey: text("public_key").notNull(),
    fingerprint: text("fingerprint").notNull(),
    kind: text("key_kind", {
      enum: ["secure_enclave", "keychain", "app_attest"],
    }).notNull(),
    appVersion: text("app_version").notNull(),
    platformVersion: text("platform_version").notNull(),
    createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
    lastSeenAt: integer("last_seen_at", { mode: "timestamp_ms" }).notNull(),
    revokedAt: integer("revoked_at", { mode: "timestamp_ms" }),
  },
  (table) => [
    uniqueIndex("installation_keys_public_key_uq").on(table.publicKey),
    uniqueIndex("installation_keys_fingerprint_uq").on(table.fingerprint),
  ],
);

export const sqliteChallenges = sqliteTable(
  "challenges",
  {
    id: text("id").primaryKey(),
    purpose: text("purpose", { enum: ["enroll", "publish"] }).notNull(),
    nonce: text("nonce").notNull(),
    installationId: text("installation_key_id").references(
      () => sqliteInstallationKeys.id,
      { onDelete: "cascade" },
    ),
    expiresAt: integer("expires_at", { mode: "timestamp_ms" }).notNull(),
    consumedAt: integer("consumed_at", { mode: "timestamp_ms" }),
    createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
  },
  (table) => [uniqueIndex("challenges_nonce_uq").on(table.nonce)],
);

export const sqliteProofs = sqliteTable(
  "proofs",
  {
    id: text("id").primaryKey(),
    slug: text("slug").notNull(),
    installationId: text("installation_key_id")
      .notNull()
      .references(() => sqliteInstallationKeys.id, { onDelete: "restrict" }),
    objectKey: text("object_key").notNull(),
    commitment: text("inner_commitment").notNull(),
    ciphertextSha256: text("ciphertext_sha256").notNull(),
    ciphertextSize: integer("ciphertext_size").notNull(),
    assuranceLevel: integer("assurance_level").notNull(),
    completionTokenHash: text("completion_token_hash").notNull(),
    revocationSecretHash: text("revocation_secret_hash").notNull(),
    receiptJson: text("receipt_json"),
    receiptSignature: text("receipt_signature"),
    receiptVersion: integer("receipt_version").notNull().default(1),
    createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
    expiresAt: integer("expires_at", { mode: "timestamp_ms" }).notNull(),
    completedAt: integer("completed_at", { mode: "timestamp_ms" }),
    revokedAt: integer("revoked_at", { mode: "timestamp_ms" }),
    deletedAt: integer("deleted_at", { mode: "timestamp_ms" }),
  },
  (table) => [
    uniqueIndex("proofs_slug_uq").on(table.slug),
    uniqueIndex("proofs_object_key_uq").on(table.objectKey),
    uniqueIndex("proofs_commitment_uq").on(table.commitment),
  ],
);

export const sqliteProofAliases = sqliteTable(
  "proof_aliases",
  {
    code: text("code").primaryKey(),
    proofId: text("proof_id")
      .notNull()
      .references(() => sqliteProofs.id, { onDelete: "cascade" }),
    createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
  },
  (table) => [uniqueIndex("proof_aliases_proof_id_uq").on(table.proofId)],
);
