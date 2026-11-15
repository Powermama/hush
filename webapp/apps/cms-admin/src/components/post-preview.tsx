// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The post as its readers will get it, full screen, as Ghost's preview
// (apps/admin/src/editor/preview, fullscreen-dialog.tsx): a header with the
// title, Desktop and Mobile, Close and Publish, and the rendered article below
// it, in a phone frame on Mobile. What the article contract still refuses is
// listed above the article.
import { Laptop, Smartphone } from "lucide-react";
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

export function PostPreview({ open, onOpenChange, preview, problems, lang, publish }: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** The CMS's rendering, or null while it is on its way. */
  preview: Preview | null;
  problems: string[];
  lang: "en" | "de";
  /** The Publish button, for a draft. */
  publish?: ReactNode;
}) {
  const [device, setDevice] = useState<"desktop" | "mobile">("desktop");
  const rendition = preview?.rendition;
  const article = rendition && <ArticlePreview heading={rendition.heading} html={rendition.html} lang={lang} className="size-full border-0" />;

  return (
    <FullscreenDialog open={open} onOpenChange={onOpenChange} title="Preview" header={
        <DialogHeader className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-4 border-b border-border-default p-4 md:grid-cols-[minmax(max-content,1fr)_minmax(0,max-content)_minmax(max-content,1fr)]">
          <DialogTitle className="text-lg">Preview</DialogTitle>
          <ToggleGroup
            className="hidden shrink-0 justify-self-center sidebar:flex" shape="pill" type="single" value={device}
            onValueChange={(value) => { if (value === "desktop" || value === "mobile") setDevice(value); }}
          >
            <ToggleGroupItem aria-label="Desktop" value="desktop"><Laptop /></ToggleGroupItem>
            <ToggleGroupItem aria-label="Mobile" value="mobile"><Smartphone /></ToggleGroupItem>
          </ToggleGroup>
          <div className="flex items-center gap-2 justify-self-end">
            <Button variant="ghost" onClick={() => onOpenChange(false)}>Close</Button>
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
