// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Ghost's publish flow, trimmed to the blog: publish now or at a time, and
// take a live or scheduled post back to draft after a confirmation.
import { useState } from "react";
import type { Post } from "@/api/cms.generated";
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription,
  AlertDialogFooter, AlertDialogHeader, AlertDialogTitle, AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";

/** The next full hour tomorrow, as a value for <input type="datetime-local">. */
function tomorrowLocal() {
  const date = new Date(Date.now() + 86_400_000);
  date.setMinutes(0, 0, 0);
  const pad = (value: number) => String(value).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:00`;
}

export function PublishMenu({ status, busy, onPublish, onSchedule, onUnpublish }: {
  status: Post["status"]; busy: boolean; onPublish: () => void; onSchedule: (at: Date) => void; onUnpublish: () => void;
}) {
  const [open, setOpen] = useState(false);
  const [when, setWhen] = useState(tomorrowLocal);
  const at = new Date(when);
  const valid = !Number.isNaN(at.getTime()) && at.getTime() > Date.now();

  if (status !== "draft") {
    return (
      <AlertDialog>
        <AlertDialogTrigger asChild><Button size="sm" variant="secondary" disabled={busy}>Unpublish</Button></AlertDialogTrigger>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{status === "published" ? "Take this post offline?" : "Cancel the schedule?"}</AlertDialogTitle>
            <AlertDialogDescription>
              {status === "published"
                ? "It returns to drafts and leaves behu.sh with the next deploy, within minutes. Its original date is kept."
                : "It returns to drafts and will not go live."}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Keep it</AlertDialogCancel>
            <AlertDialogAction variant="destructive" onClick={onUnpublish}>{status === "published" ? "Unpublish" : "Cancel schedule"}</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    );
  }

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild><Button size="sm" className="bg-[var(--publish)] text-white hover:bg-[var(--publish)]/90" disabled={busy}>Publish</Button></PopoverTrigger>
      <PopoverContent align="end" className="w-72">
        <div className="grid gap-4">
          <div>
            <p className="text-sm font-semibold">Ready to go live?</p>
            <p className="mt-1 text-xs text-muted-foreground">behu.sh rebuilds within minutes and search engines are told.</p>
          </div>
          <Button onClick={() => { setOpen(false); onPublish(); }}>Publish now</Button>
          <div className="grid gap-1.5">
            <Label htmlFor="schedule-at" className="text-[13px]">Or schedule it</Label>
            <Input id="schedule-at" type="datetime-local" value={when} onChange={(event) => setWhen(event.target.value)} />
            <Button variant="outline" disabled={!valid} onClick={() => { setOpen(false); onSchedule(at); }}>Schedule</Button>
          </div>
        </div>
      </PopoverContent>
    </Popover>
  );
}
