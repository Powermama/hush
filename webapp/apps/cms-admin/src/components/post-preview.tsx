// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The post as its readers will get it, full screen, as Ghost's preview
// (apps/admin/src/editor/preview, fullscreen-dialog.tsx): a header with the
// title, Desktop and Mobile, Close and Publish, and the rendered article below
// it, in a phone frame on Mobile. What the article contract still refuses is
// listed above the article. For a draft, the owner approves what they see here
// for an agent to schedule or publish (hush's own step; Ghost has no agents).
import { Check, Laptop, Smartphone } from "lucide-react";
import { useState, type ReactNode } from "react";
import type { Preview } from "@/api/cms.generated";
import { ArticlePreview } from "@/components/article-preview";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { FullscreenDialog } from "@/components/fullscreen-dialog";
import { DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { LoadingIndicator } from "@/components/ui/loading-indicator";
import { PreviewChrome } from "@/components/ui/preview-chrome";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { cn } from "@/lib/utils";

export function PostPreview({ open, onOpenChange, preview, problems, lang, lead, approval, publish }: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** The CMS's rendering, or null while it is on its way. */
  preview: Preview | null;
  problems: string[];
  lang: "en" | "de";
  /** The excerpt, shown as the article's lead as on behu.sh. */
  lead: string;
  /** The owner's approval of a draft for agents: whether it covers the post as it is, or lapsed since. */
  approval?: { current: boolean; lapsed: boolean; busy: boolean; onApprove: () => void };
  /** The Publish button, for a draft. */
  publish?: ReactNode;
}) {
  const [device, setDevice] = useState<"desktop" | "mobile">("desktop");
  const rendition = preview?.rendition;
  const article = rendition && <ArticlePreview heading={rendition.heading} lead={lead} html={rendition.html} lang={lang} className="size-full border-0" />;

  return (
    <FullscreenDialog open={open} onOpenChange={onOpenChange} title="Preview" header={
        <DialogHeader className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-4 border-b border-border-default p-4 md:grid-cols-[minmax(max-content,1fr)_minmax(0,max-content)_minmax(max-content,1fr)]">
          {/* Below 380px the buttons need the room; the title still names the dialog. */}
          <DialogTitle className="min-w-0 truncate text-lg max-[379px]:sr-only">Preview</DialogTitle>
          <ToggleGroup
            className="hidden shrink-0 justify-self-center sidebar:flex" shape="pill" type="single" value={device}
            onValueChange={(value) => { if (value === "desktop" || value === "mobile") setDevice(value); }}
          >
            <ToggleGroupItem aria-label="Desktop" value="desktop"><Laptop /></ToggleGroupItem>
            <ToggleGroupItem aria-label="Mobile" value="mobile"><Smartphone /></ToggleGroupItem>
          </ToggleGroup>
          <div className="flex items-center gap-2 justify-self-end">
            <Button variant="ghost" onClick={() => onOpenChange(false)}>Close</Button>
            {approval && (approval.current ? (
              <span className="flex h-(--control-height) items-center gap-1.5 px-2.5 text-sm font-medium text-state-success"><Check className="size-4" />Approved</span>
            ) : (
              <Button variant="outline" className="shrink-0" disabled={approval.busy || problems.length > 0} onClick={approval.onApprove}
                aria-label={approval.lapsed ? "Approve again" : "Approve"} title="Lets an agent schedule or publish the post as it is now">
                {/* The narrowest phones have room for one word. One span, so the button's gap stays out of the label. */}
                <span>Approve{approval.lapsed && <span className="max-[359px]:hidden"> again</span>}</span>
              </Button>
            ))}
            {publish}
          </div>
        </DialogHeader>
      }>
        <div className={cn("flex min-h-0 flex-col overflow-auto", device === "mobile" ? "items-center bg-muted p-6" : "bg-surface-panel")}>
          {problems.length > 0 && (
            <div className={cn("w-full", device === "desktop" && "px-4 pt-4")}>
              <Alert variant="destructive" className="mx-auto mb-4 max-w-[740px] bg-background">
                <AlertTitle>Not ready to publish</AlertTitle>
                <AlertDescription><ul className="mt-1 list-disc pl-4">{problems.map((problem) => <li key={problem}>{problem}</li>)}</ul></AlertDescription>
              </Alert>
            </div>
          )}
          {!preview ? (
            <div role="status" aria-label="Preparing preview" className="flex grow items-center justify-center"><LoadingIndicator size="lg" /></div>
          ) : !article ? (
            <p className="m-auto max-w-sm p-6 text-center text-base text-muted-foreground">The preview appears once the article meets the contract.</p>
          ) : device === "mobile" ? (
            <PreviewChrome device="mobile" className="max-w-full shrink-0">{article}</PreviewChrome>
          ) : (
            <div className="min-h-0 grow">{article}</div>
          )}
        </div>
    </FullscreenDialog>
  );
}
