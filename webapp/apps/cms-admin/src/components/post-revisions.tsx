// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Every save and status change, newest first; any one can become the current
// version again (for a live post, only if it still meets the contract).
import { HistoryIcon } from "lucide-react";
import { toast } from "sonner";
import { restoreRevision, useListRevisions, type Post, type Revision } from "@/api/cms.generated";
import { CmsError } from "@/api/fetcher";
import { Button } from "@/components/ui/button";

const timeFormat = new Intl.DateTimeFormat("en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
const actorName = (actor: string) => actor.replace(/^github:/, "").replace(/^token:/, "token ");

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

  return (
    <section className="grid gap-3">
      <h3 className="flex items-center gap-2 text-sm font-semibold"><HistoryIcon className="size-4" />History</h3>
      <ul className="grid gap-1">
        {items.slice(0, 30).map((revision, index) => (
          <li key={revision.id} className="flex items-center gap-2 rounded-md px-2 py-1.5 text-xs hover:bg-muted">
            <span className="min-w-0 flex-1">
              <span className="font-medium">{timeFormat.format(new Date(revision.createdAt))}</span>
              <span className="text-muted-foreground"> · {revision.status} · {actorName(revision.actor)}</span>
            </span>
            {index === 0
              ? <span className="text-muted-foreground">Current</span>
              : <Button variant="ghost" size="sm" className="h-7" onClick={() => void restore(revision)}>Restore</Button>}
          </li>
        ))}
      </ul>
    </section>
  );
}
