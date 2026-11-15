// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// A dialog that covers the whole window, as Ghost's editor uses for preview and
// publishing (apps/admin/src/editor/fullscreen-dialog.tsx): Shade's dialog with
// a full-viewport frame. A click outside never closes it (there is no outside);
// Escape and the caller's Close do.
import type { ReactNode } from "react";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { cn } from "@/lib/utils";

// Overrides Shade's centred, sized dialog surface with a full-viewport one.
const frame = "top-0 left-0 h-dvh w-full max-w-none translate-0 gap-0 rounded-none border-0 p-0 shadow-none sm:rounded-none";

export function FullscreenDialog({ open, onOpenChange, title, header, className, children }: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** The dialog's name; shown in the header when there is one, else read by screen readers only. */
  title: string;
  /** A header row of its own above the body (the preview); without it the body draws its own (publishing). */
  header?: ReactNode;
  className?: string;
  children: ReactNode;
}) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent
        className={cn(frame, header ? "grid-rows-[auto_1fr]" : "grid-rows-[1fr] overflow-y-auto", className)}
        onInteractOutside={(event) => event.preventDefault()}
        aria-describedby={undefined}
      >
        {header ?? <DialogTitle className="sr-only">{title}</DialogTitle>}
        {children}
      </DialogContent>
    </Dialog>
  );
}
