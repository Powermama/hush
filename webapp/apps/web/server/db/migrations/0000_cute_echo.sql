CREATE TYPE "public"."challenge_purpose" AS ENUM('enroll', 'publish');--> statement-breakpoint
CREATE TYPE "public"."key_kind" AS ENUM('secure_enclave', 'keychain', 'app_attest');--> statement-breakpoint
CREATE TABLE "challenges" (
	"id" uuid PRIMARY KEY NOT NULL,
	"purpose" "challenge_purpose" NOT NULL,
	"nonce" text NOT NULL,
	"installation_key_id" uuid,
	"expires_at" timestamp with time zone NOT NULL,
	"consumed_at" timestamp with time zone,
	"created_at" timestamp with time zone NOT NULL
);
--> statement-breakpoint
CREATE TABLE "installation_keys" (
	"id" uuid PRIMARY KEY NOT NULL,
	"public_key" text NOT NULL,
	"fingerprint" text NOT NULL,
	"key_kind" "key_kind" NOT NULL,
	"app_version" text NOT NULL,
	"platform_version" text NOT NULL,
	"created_at" timestamp with time zone NOT NULL,
	"last_seen_at" timestamp with time zone NOT NULL,
	"revoked_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "proofs" (
	"id" uuid PRIMARY KEY NOT NULL,
	"slug" text NOT NULL,
	"installation_key_id" uuid NOT NULL,
	"object_key" text NOT NULL,
	"inner_commitment" text NOT NULL,
	"ciphertext_sha256" text NOT NULL,
	"ciphertext_size" bigint NOT NULL,
	"assurance_level" smallint NOT NULL,
	"completion_token_hash" text NOT NULL,
	"revocation_secret_hash" text NOT NULL,
	"receipt_json" text,
	"receipt_signature" text,
	"receipt_version" integer DEFAULT 1 NOT NULL,
	"created_at" timestamp with time zone NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"completed_at" timestamp with time zone,
	"revoked_at" timestamp with time zone,
	"deleted_at" timestamp with time zone
);
--> statement-breakpoint
ALTER TABLE "challenges" ADD CONSTRAINT "challenges_installation_key_id_installation_keys_id_fk" FOREIGN KEY ("installation_key_id") REFERENCES "public"."installation_keys"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "proofs" ADD CONSTRAINT "proofs_installation_key_id_installation_keys_id_fk" FOREIGN KEY ("installation_key_id") REFERENCES "public"."installation_keys"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "challenges_nonce_uq" ON "challenges" USING btree ("nonce");--> statement-breakpoint
CREATE INDEX "challenges_expiry_idx" ON "challenges" USING btree ("expires_at");--> statement-breakpoint
CREATE INDEX "challenges_installation_idx" ON "challenges" USING btree ("installation_key_id");--> statement-breakpoint
CREATE UNIQUE INDEX "installation_keys_public_key_uq" ON "installation_keys" USING btree ("public_key");--> statement-breakpoint
CREATE UNIQUE INDEX "installation_keys_fingerprint_uq" ON "installation_keys" USING btree ("fingerprint");--> statement-breakpoint
CREATE UNIQUE INDEX "proofs_slug_uq" ON "proofs" USING btree ("slug");--> statement-breakpoint
CREATE UNIQUE INDEX "proofs_object_key_uq" ON "proofs" USING btree ("object_key");--> statement-breakpoint
CREATE UNIQUE INDEX "proofs_commitment_uq" ON "proofs" USING btree ("inner_commitment");--> statement-breakpoint
CREATE INDEX "proofs_installation_idx" ON "proofs" USING btree ("installation_key_id");--> statement-breakpoint
CREATE INDEX "proofs_expiry_idx" ON "proofs" USING btree ("expires_at");