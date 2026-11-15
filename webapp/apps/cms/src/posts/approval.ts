// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// What agents (every token, auth/tokens.ts) may do: change drafts, and
// schedule or publish only what the owner approved. An approval names the
// content it covers by a hash of the post's fields and images, so any later
// change to either leaves it lapsed, whoever makes it.
import { createHash } from "node:crypto";
import { isAgent } from "../auth/tokens";
import { PostError } from "./errors";
import type { PostFields } from "./fields";
import type { Post } from "./service";

export function contentHash(fields: PostFields, images: ReadonlyArray<{ name: string; sha256: string }>) {
  const media = [...images].sort((a, b) => a.name.localeCompare(b.name)).map(({ name, sha256 }) => [name, sha256]);
  return createHash("sha256").update(JSON.stringify({ fields, media })).digest("hex");
}

export type Approval = { approvedBy: string; approvedAt: Date; current: boolean };

/** An agent schedules or publishes only what the owner approved, as it is now. */
export function requireApproval(actor: string, post: Post) {
  if (!isAgent(actor)) return;
  if (!post.approval) {
    throw new PostError(403, "approval_required", "The owner has not approved this post. Ask the owner to approve it in the admin, then schedule or publish it.");
  }
  if (!post.approval.current) {
    throw new PostError(403, "approval_lapsed", "The post changed after the owner approved it. Ask the owner to approve it again.");
  }
}

/** An agent changes drafts only; a scheduled or published post changes through the owner. */
export function requireDraftFor(actor: string, post: Pick<Post, "status">) {
  if (isAgent(actor) && post.status !== "draft") {
    throw new PostError(403, "live_post", "Only the owner changes a scheduled or published post, in the admin.");
  }
}
