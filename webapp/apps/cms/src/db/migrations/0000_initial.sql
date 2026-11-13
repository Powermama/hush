CREATE TYPE "public"."post_status" AS ENUM('draft', 'scheduled', 'published');--> statement-breakpoint
CREATE TYPE "public"."token_scope" AS ENUM('posts:read', 'posts:write', 'posts:publish');--> statement-breakpoint
CREATE TABLE "api_token_scopes" (
	"token_id" uuid NOT NULL,
	"scope" "token_scope" NOT NULL,
	CONSTRAINT "api_token_scopes_token_id_scope_pk" PRIMARY KEY("token_id","scope")
);
--> statement-breakpoint
CREATE TABLE "api_tokens" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"name" text NOT NULL,
	"token_hash" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"expires_at" timestamp with time zone,
	"last_used_at" timestamp with time zone,
	"revoked_at" timestamp with time zone,
	CONSTRAINT "api_tokens_token_hash_unique" UNIQUE("token_hash")
);
--> statement-breakpoint
CREATE TABLE "post_renditions" (
	"post_id" uuid PRIMARY KEY NOT NULL,
	"heading" text NOT NULL,
	"html" text NOT NULL,
	"toc" jsonb NOT NULL,
	"reading_minutes" integer NOT NULL,
	"rendered_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "post_revisions" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"post_id" uuid NOT NULL,
	"status" "post_status" NOT NULL,
	"snapshot" jsonb NOT NULL,
	"actor" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "post_secondary_keywords" (
	"post_id" uuid NOT NULL,
	"position" smallint NOT NULL,
	"keyword" text NOT NULL,
	CONSTRAINT "post_secondary_keywords_post_id_position_pk" PRIMARY KEY("post_id","position")
);
--> statement-breakpoint
CREATE TABLE "posts" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"lang" text NOT NULL,
	"slug" text NOT NULL,
	"status" "post_status" DEFAULT 'draft' NOT NULL,
	"title" text NOT NULL,
	"description" text NOT NULL,
	"keyword" text NOT NULL,
	"type" text NOT NULL,
	"cluster" text NOT NULL,
	"author" text NOT NULL,
	"image_alt" text NOT NULL,
	"markdown" text NOT NULL,
	"published_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "api_token_scopes" ADD CONSTRAINT "api_token_scopes_token_id_api_tokens_id_fk" FOREIGN KEY ("token_id") REFERENCES "public"."api_tokens"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "post_renditions" ADD CONSTRAINT "post_renditions_post_id_posts_id_fk" FOREIGN KEY ("post_id") REFERENCES "public"."posts"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "post_revisions" ADD CONSTRAINT "post_revisions_post_id_posts_id_fk" FOREIGN KEY ("post_id") REFERENCES "public"."posts"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "post_secondary_keywords" ADD CONSTRAINT "post_secondary_keywords_post_id_posts_id_fk" FOREIGN KEY ("post_id") REFERENCES "public"."posts"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "post_revisions_post_created" ON "post_revisions" USING btree ("post_id","created_at");--> statement-breakpoint
CREATE UNIQUE INDEX "posts_lang_slug" ON "posts" USING btree ("lang","slug");--> statement-breakpoint
CREATE INDEX "posts_status_published_at" ON "posts" USING btree ("status","published_at");