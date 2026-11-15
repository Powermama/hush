// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Publishing, full screen, as Ghost's publish flow (apps/admin/src/editor/publish):
// the options (on the site; now or at a time), then a final review with the one
// button that publishes, and, for a live post, the way back to a draft. Ghost's
// newsletter and member options are left out: a hush article goes to the site.
// What the article contract refuses is shown where the button was pressed.
import { ArrowLeft, ArrowRight, ChevronDown, Clock, Send } from "lucide-react";
import { useId, useState, type ReactNode } from "react";
import { FullscreenDialog } from "@/components/fullscreen-dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { LoadingIndicator } from "@/components/ui/loading-indicator";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import { cn } from "@/lib/utils";

/** What the CMS answered when it refused: its message and the contract's problems. */
export type Refusal = { message: string; problems: string[] };

const dayTime = new Intl.DateTimeFormat("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });
const monthDay = new Intl.DateTimeFormat("en-US", { month: "long", day: "numeric" });
const relative = new Intl.RelativeTimeFormat("en", { numeric: "auto" });
const pad = (value: number) => String(value).padStart(2, "0");
const timeZone = new Intl.DateTimeFormat("en", { timeZoneName: "short" }).formatToParts(new Date()).find((part) => part.type === "timeZoneName")?.value ?? "";

/** "14 Nov 2026 at 15:00", as Ghost writes a date and time. */
export const atTime = (date: Date) => dayTime.format(date).replace(/, (\d)/, " at $1");

/** "November 14th", for the confirm button. */
function ordinalDay(date: Date) {
  const day = date.getDate();
  const suffix = day % 10 === 1 && day !== 11 ? "st" : day % 10 === 2 && day !== 12 ? "nd" : day % 10 === 3 && day !== 13 ? "rd" : "th";
  return `${monthDay.format(date)}${suffix}`;
}

/** "In 10 minutes", "Tomorrow", as Ghost names a scheduled time in its row. */
function fromNow(date: Date) {
  const minutes = Math.round((date.getTime() - Date.now()) / 60_000);
  const text = Math.abs(minutes) < 60 ? relative.format(minutes, "minute")
    : Math.abs(minutes) < 24 * 60 ? relative.format(Math.round(minutes / 60), "hour")
      : relative.format(Math.round(minutes / 1440), "day");
  return text.charAt(0).toUpperCase() + text.slice(1);
}

/** Ten minutes from now, on the minute: Ghost's first suggestion for a schedule. */
function soon() {
  const date = new Date(Date.now() + 10 * 60_000);
  date.setSeconds(0, 0);
  return date;
}

/** One row of the options: an icon, what is chosen, and its choices when open. */
function PublishSetting({ icon, title, open, onToggle, children }: { icon: ReactNode; title: ReactNode; open?: boolean; onToggle?: () => void; children?: ReactNode }) {
  const interactive = Boolean(onToggle);
  return (
    <div className="flex flex-col border-b border-border-default last:border-b-0">
      <button
        type="button" aria-expanded={interactive ? open : undefined} disabled={!interactive} onClick={onToggle}
        className="flex w-full cursor-pointer items-center gap-3 px-1 py-4 text-left disabled:cursor-default"
      >
        <span className="shrink-0">{icon}</span>
        <span className="grow text-lg font-medium">{title}</span>
        {interactive && <ChevronDown className={cn("size-4 shrink-0 transition-transform", open && "rotate-180")} />}
      </button>
      {open && children && <div className="pr-1 pb-5 pl-8 motion-safe:animate-in motion-safe:duration-200 motion-safe:fade-in motion-safe:slide-in-from-top-1">{children}</div>}
    </div>
  );
}

function Heading({ children }: { children: ReactNode }) {
  return <h2 className="text-5xl leading-tighter font-bold tracking-tight">{children}</h2>;
}

function Failure({ refusal }: { refusal: Refusal }) {
  return (
    <div role="alert" className="rounded-lg border border-destructive/30 bg-destructive/5 p-4 text-base text-destructive">
      <p className="font-semibold">{refusal.message}</p>
      {refusal.problems.length > 0 && <ul className="mt-2 list-disc pl-5">{refusal.problems.map((problem) => <li key={problem}>{problem}</li>)}</ul>}
    </div>
  );
}

export function PublishFlow({ open, onClose, mode, publishedAt, onPreview, onPublish, onUnpublish }: {
  open: boolean;
  onClose: () => void;
  /** Publishing a draft, or taking a live post back to a draft. */
  mode: "publish" | "unpublish-published" | "unpublish-scheduled";
  /** When the live post went or goes live. */
  publishedAt?: Date;
  onPreview?: () => void;
  /** Publishes now, or schedules for a time; answers with what was refused, if anything. */
  onPublish: (at?: Date) => Promise<Refusal | undefined>;
  onUnpublish: () => Promise<Refusal | undefined>;
}) {
  const id = useId();
  const [step, setStep] = useState<"options" | "confirm">("options");
  const [timeOpen, setTimeOpen] = useState(false);
  const [scheduled, setScheduled] = useState(false);
  const [at, setAt] = useState(soon);
  const [running, setRunning] = useState(false);
  const [refusal, setRefusal] = useState<Refusal | undefined>();
  const future = at.getTime() > Date.now();

  const close = () => {
    if (running) return;
    setStep("options");
    setRefusal(undefined);
    onClose();
  };

  const confirm = async () => {
    setRunning(true);
    setRefusal(undefined);
    const refused = mode === "publish" ? await onPublish(scheduled ? at : undefined) : await onUnpublish();
    if (refused) { setRunning(false); setRefusal(refused); return; }
    // A publish or schedule that lands goes to the posts list, as Ghost's editor does
    // (showCompletion={false}): the button keeps running until the editor unmounts.
    if (mode === "publish") return;
    setRunning(false);
    setStep("options");
    onClose();
  };

  const setDay = (value: string) => {
    const [year, month, day] = value.split("-").map(Number);
    if (!year || !month || !day) return;
    const next = new Date(at);
    next.setFullYear(year, month - 1, day);
    setAt(next);
  };
  const setTime = (value: string) => {
    const [hours, minutes] = value.split(":").map(Number);
    if (hours === undefined || minutes === undefined || Number.isNaN(hours) || Number.isNaN(minutes)) return;
    const next = new Date(at);
    next.setHours(hours, minutes, 0, 0);
    setAt(next);
  };

  const title = mode === "publish" ? "Publish" : mode === "unpublish-scheduled" ? "Unschedule" : "Unpublish";

  return (
    <FullscreenDialog open={open} onOpenChange={(next) => { if (!next) close(); }} title={title}>
      <div className="relative min-h-full">
        <div className="absolute inset-x-0 top-0 flex items-center justify-between p-4">
          <h2 aria-hidden className="text-lg font-semibold tracking-tight">{title}</h2>
          <div className="flex items-center gap-2">
            <Button variant="ghost" disabled={running} onClick={close}>Close</Button>
            {mode === "publish" && onPreview && <Button variant="outline" className="w-20 shrink-0" onClick={onPreview}>Preview</Button>}
          </div>
        </div>

        <div className="mx-auto flex w-full max-w-156 flex-col gap-10 px-6 pt-[max(96px,18vh)] pb-16">
          {mode !== "publish" ? (
            <>
              <Heading>This post has been <span className="text-publish-accent">{mode === "unpublish-scheduled" ? "scheduled" : "published"}</span></Heading>
              <p className="text-lg text-pretty">
                {mode === "unpublish-scheduled"
                  ? <>Your post will be published on your site on <strong>{publishedAt && atTime(publishedAt)}</strong>.</>
                  : <>Your post was published on your site on <strong>{publishedAt && atTime(publishedAt)}</strong>.</>}
              </p>
              {refusal && <Failure refusal={refusal} />}
              <div>
                <Button size="lg" variant="secondary" disabled={running} onClick={() => void confirm()}>
                  {running ? <LoadingIndicator color="current" size="sm" /> : null}
                  {mode === "unpublish-scheduled" ? "Unschedule and revert to draft" : "Unpublish and revert to private draft"}
                  {!running && <ArrowRight />}
                </Button>
              </div>
            </>
          ) : step === "options" ? (
            <>
              <div>
                <Heading><span className="text-publish-accent">Ready, set, publish.</span></Heading>
                <Heading>Share it with the world.</Heading>
              </div>
              <div className="flex flex-col">
                <PublishSetting icon={<Send className="size-4" />} title="Publish on site" />
                <PublishSetting
                  icon={<Clock className="size-4" />} title={scheduled ? fromNow(at) : "Right now"}
                  open={timeOpen} onToggle={() => setTimeOpen((value) => !value)}
                >
                  <div className="grid grid-cols-1 items-end gap-3 md:grid-cols-[auto_minmax(0,1fr)]">
                    <RadioGroup value={scheduled ? "schedule" : "now"} onValueChange={(value) => { setScheduled(value === "schedule"); if (value === "schedule" && !future) setAt(soon()); }}>
                      <div className="flex items-center gap-2"><RadioGroupItem id={`${id}-now`} value="now" /><Label htmlFor={`${id}-now`}>Set it live now</Label></div>
                      <div className="flex items-center gap-2"><RadioGroupItem id={`${id}-schedule`} value="schedule" /><Label htmlFor={`${id}-schedule`}>Schedule for later</Label></div>
                    </RadioGroup>
                    {scheduled && (
                      <div className="flex w-full max-w-80 gap-2 md:translate-y-2 md:justify-self-end">
                        <Input aria-label="Publish date" type="date" className="min-w-0 flex-1" value={`${at.getFullYear()}-${pad(at.getMonth() + 1)}-${pad(at.getDate())}`} onChange={(event) => setDay(event.target.value)} />
                        <Input aria-label="Publish time" type="time" className="w-28 shrink-0" value={`${pad(at.getHours())}:${pad(at.getMinutes())}`} onChange={(event) => setTime(event.target.value)} />
                        <span className="self-center text-sm whitespace-nowrap text-muted-foreground">{timeZone}</span>
                      </div>
                    )}
                  </div>
                  {scheduled && !future && <p className="mt-3 text-sm text-destructive">Choose a time in the future.</p>}
                </PublishSetting>
              </div>
              <div>
                <Button size="lg" disabled={scheduled && !future} onClick={() => { setRefusal(undefined); setStep("confirm"); }}>Continue, final review <ArrowRight /></Button>
              </div>
            </>
          ) : (
            <>
              <div>
                <Heading><span className="text-publish-accent">Ready, set, publish.</span></Heading>
                <Heading>Share it with the world.</Heading>
              </div>
              <p className="text-lg text-pretty">
                {scheduled ? <>On <strong>{atTime(at)}</strong> your post will be published on your site.</> : "Your post will be published on your site."}
              </p>
              {refusal && <Failure refusal={refusal} />}
              <div className="flex flex-wrap items-center justify-between gap-2">
                <Button size="lg" variant="secondary" disabled={running} onClick={() => setStep("options")}><ArrowLeft />Back to settings</Button>
                <Button
                  size="lg" disabled={running} onClick={() => void confirm()}
                  className="ml-auto h-auto min-h-11 max-w-full bg-publish-accent py-2 whitespace-normal text-white hover:bg-publish-accent/90"
                >
                  {running
                    ? <><LoadingIndicator color="current" size="sm" />{scheduled ? "Scheduling" : "Publishing"}</>
                    : scheduled ? `Publish post, on ${ordinalDay(at)}` : "Publish post, right now"}
                </Button>
              </div>
            </>
          )}
        </div>
      </div>
    </FullscreenDialog>
  );
}
