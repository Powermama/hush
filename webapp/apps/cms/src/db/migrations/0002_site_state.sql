CREATE TABLE "site_changes" (
	"revision" bigint NOT NULL,
	"path" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "site_changes_revision_path_pk" PRIMARY KEY("revision","path")
);
--> statement-breakpoint
CREATE TABLE "site_state" (
	"id" smallint PRIMARY KEY DEFAULT 1 NOT NULL,
	"revision" bigint DEFAULT 0 NOT NULL,
	"notified_revision" bigint DEFAULT 0 NOT NULL,
	"deploy_revision" bigint,
	"deploy_requested_at" timestamp with time zone,
	CONSTRAINT "site_state_single_row" CHECK ("site_state"."id" = 1)
);
--> statement-breakpoint
INSERT INTO "site_state" ("id") VALUES (1);
