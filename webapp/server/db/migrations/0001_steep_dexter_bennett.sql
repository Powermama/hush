CREATE TABLE "proof_aliases" (
	"code" text PRIMARY KEY NOT NULL,
	"proof_id" uuid NOT NULL,
	"created_at" timestamp with time zone NOT NULL
);
--> statement-breakpoint
ALTER TABLE "proof_aliases" ADD CONSTRAINT "proof_aliases_proof_id_proofs_id_fk" FOREIGN KEY ("proof_id") REFERENCES "public"."proofs"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "proof_aliases_proof_id_uq" ON "proof_aliases" USING btree ("proof_id");