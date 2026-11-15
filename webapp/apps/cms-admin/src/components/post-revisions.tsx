// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Every save and status change, newest first, drawn as Ghost's post history
// rows (apps/admin/src/editor/settings/post-history-modal.tsx): the time, its
// labels (Latest, Published, Unpublished) and who wrote it. Any earlier one can
// become the current version again (for a live post, only if it still meets
// the contract).
import { toast } from "sonner";
import { restoreRevision, useListRevisions, type Post, type Revision } from "@/api/cms.generated";
import { CmsError } from "@/api/fetcher";
import { Avatar } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";

const timeFormat = new Intl.DateTimeFormat("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });
const actorName = (actor: string) => actor.replace(/^github:/, "").replace(/^token:/, "token ");

/** Ghost's labels: the newest, the version that took the post live, and the one that took it back. */
function labels(revision: Revision, index: number, older?: Revision) {
  const tags: { text: string; variant: "secondary" | "success" | "warning" }[] = [];
  if (index === 0) tags.push({ text: "Latest", variant: "secondary" });
  if (revision.status === "published" && older?.status !== "published") tags.push({ text: "Published", variant: "success" });
  if (revision.status === "draft" && older && older.status !== "draft") tags.push({ text: "Unpublished", variant: "warning" });
  return tags;
}

export function PostRevisions({ postId, onRestored }: { postId: string; onRestored: (post: Post) => void | Promise<void> }) {
  const revisions = useListRevisions(postId);
  const items: Revision[] = revisions.data?.data && "revisions" in revisions.data.data ? revisions.data.data.revisions : [];

  const restore = async (revision: Revision) => {
    try {
      const result = await restoreRevision(postId, revision.id);
      await onRestored(result.data as Post);
      toast.success("Revision restored");
    } catch (error) {
      toast.error(error instanceof CmsError ? error.message : "The revision could not be restored.");
    }
  };

  if (revisions.isPending) return <p className="px-2 text-sm text-text-secondary">Loading…</p>;
  return (
    <ul className="grid gap-px">
      {items.slice(0, 30).map((revision, index) => {
        const actor = actorName(revision.actor);
        return (
          <li key={revision.id} className="relative rounded-md px-3 py-2 hover:bg-interactive-hover">
            <div className="flex flex-wrap items-center gap-2">
              <span className="text-sm font-medium whitespace-nowrap">{timeFormat.format(new Date(revision.createdAt))}</span>
              {labels(revision, index, items[index + 1]).map((tag) => <Badge key={tag.text} variant={tag.variant}>{tag.text}</Badge>)}
            </div>
            <div className="mt-1 flex min-h-7 items-center gap-2 pr-20">
              <Avatar className="size-6 shrink-0" initials={actor.slice(0, 1).toUpperCase()} colorSeed={actor} />
              <span className="truncate text-sm text-text-secondary">{actor}</span>
            </div>
            {index > 0 && (
              <Button size="sm" variant="outline" className="absolute right-3 bottom-2 bg-surface-elevated-2" onClick={() => void restore(revision)}>Restore</Button>
            )}
          </li>
        );
      })}
    </ul>
  );
}
