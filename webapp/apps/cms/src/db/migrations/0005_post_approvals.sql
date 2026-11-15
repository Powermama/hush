CREATE TABLE "post_approvals" (
	"post_id" uuid PRIMARY KEY NOT NULL,
	"content_hash" text NOT NULL,
	"approved_by" text NOT NULL,
	"approved_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "post_approvals" ADD CONSTRAINT "post_approvals_post_id_posts_id_fk" FOREIGN KEY ("post_id") REFERENCES "public"."posts"("id") ON DELETE cascade ON UPDATE no action;