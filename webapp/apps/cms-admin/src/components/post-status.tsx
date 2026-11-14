// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import type { Post } from "@/api/cms.generated";
import { cn } from "@/lib/utils";

const dateFormat = new Intl.DateTimeFormat("en-GB", { day: "numeric", month: "short", year: "numeric" });
const dateTimeFormat = new Intl.DateTimeFormat("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });

/** Ghost's status wording: what the post is and when. */
export function postStatusLine(post: Pick<Post, "status" | "publishedAt" | "updatedAt">) {
  if (post.status === "published") return `Published ${dateFormat.format(new Date(post.publishedAt!))}`;
  if (post.status === "scheduled") return `Scheduled for ${dateTimeFormat.format(new Date(post.publishedAt!))}`;
  return `Draft, edited ${dateFormat.format(new Date(post.updatedAt))}`;
}

const tones = {
  draft: "bg-gray-100 text-gray-900",
  scheduled: "bg-blue-100 text-blue-700",
  published: "bg-green-100 text-green-700",
} as const;

export function PostStatusBadge({ status, className }: { status: Post["status"]; className?: string }) {
  return (
    <span className={cn("inline-flex h-5 items-center rounded-sm px-1.5 text-[11px] font-semibold uppercase tracking-wide", tones[status], className)}>
      {status}
    </span>
  );
}
