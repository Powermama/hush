// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The settings navigation that takes the sidebar's place while Settings is
// open, as Ghost Admin's (apps/admin/src/settings/layout/sidebar.tsx,
// components/exit-settings-button.tsx): back to the app, "Search settings"
// ("/" focuses it, Escape blurs it), and each group's sections, the one in
// view marked.
import { useNavigate } from "@tanstack/react-router";
import { ArrowLeft, Blocks, Search, UserRound, X } from "lucide-react";
import { useEffect, useRef, type ReactNode } from "react";
import { Button } from "@/components/ui/button";
import { InputGroup, InputGroupAddon, InputGroupButton, InputGroupInput } from "@/components/ui/input-group";
import { Kbd } from "@/components/ui/kbd";
import { SidebarMenu, SidebarMenuButton, SidebarMenuItem } from "@/components/ui/sidebar";
import { cn } from "@/lib/utils";
import { settingsSections, useSettings, type SettingsSectionId } from "./settings-context";

const icons: Record<SettingsSectionId, ReactNode> = { account: <UserRound />, integrations: <Blocks /> };

/** Back to the posts, as Ghost's "Back to app (ESC)". */
export function ExitSettingsButton() {
  const navigate = useNavigate();
  return (
    <Button aria-label="Back to app" title="Back to app (ESC)" className="size-(--control-height) shrink-0 rounded-full" size="icon" type="button" variant="outline" onClick={() => void navigate({ to: "/" })}>
      <ArrowLeft />
    </Button>
  );
}

export function SettingsSearchInput({ className, inputRef }: { className?: string; inputRef?: React.RefObject<HTMLInputElement | null> }) {
  const { filter, setFilter } = useSettings();
  const ownRef = useRef<HTMLInputElement>(null);
  const ref = inputRef ?? ownRef;
  return (
    <InputGroup className={cn("rounded-full border-control-border bg-surface-elevated-2 shadow-sm", className)}>
      <InputGroupAddon align="inline-start"><Search aria-hidden="true" className="size-4" /></InputGroupAddon>
      <InputGroupInput
        ref={ref} aria-label="Search settings" autoComplete="off" autoCorrect="off" placeholder="Search settings" value={filter}
        onChange={(event) => { setFilter(event.target.value); if (event.target.value) document.getElementById("settings-scroller")?.scrollTo({ top: 0 }); }}
        onKeyDown={(event) => { if (event.key === "Escape" && filter) { event.currentTarget.blur(); event.stopPropagation(); } }}
      />
      <InputGroupAddon align="inline-end">
        {filter
          ? <InputGroupButton aria-label="Clear query" size="icon-xs" onClick={() => { setFilter(""); ref.current?.focus(); }}><X aria-hidden="true" /></InputGroupButton>
          : <Kbd className="hidden tablet:inline-flex">/</Kbd>}
      </InputGroupAddon>
    </InputGroup>
  );
}

/** The back button and search row that leads the settings navigation. */
export function SettingsHeader({ className, inputRef }: { className?: string; inputRef?: React.RefObject<HTMLInputElement | null> }) {
  return (
    <div className={cn("flex items-center gap-2", className)}>
      <ExitSettingsButton />
      <SettingsSearchInput className="flex-1" inputRef={inputRef} />
    </div>
  );
}

export function NoSearchResult({ className }: { className?: string }) {
  const { filter } = useSettings();
  return (
    <div className={cn("text-base text-muted-foreground", className)}>
      <h2 className="mb-2 text-base font-semibold tracking-normal text-foreground">No result</h2>
      <div>{`We couldn't find any setting matching '${filter}'.`}</div>
    </div>
  );
}

export function SettingsNav() {
  const { isVisible, current, jumpTo, setFilter } = useSettings();
  const inputRef = useRef<HTMLInputElement>(null);
  const groups = [...new Set(settingsSections.map((section) => section.group))];
  const noResult = settingsSections.every((section) => !isVisible(section.id));

  // "/" focuses the search, outside text fields; it starts focused, as in Ghost.
  useEffect(() => {
    inputRef.current?.focus();
    const onKeyDown = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement;
      if (event.key !== "/" || target.isContentEditable || ["INPUT", "TEXTAREA"].includes(target.nodeName)) return;
      event.preventDefault();
      inputRef.current?.focus();
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, []);
  useEffect(() => () => setFilter(""), [setFilter]);

  return (
    <div className="flex min-h-0 flex-1 flex-col" data-testid="settings-nav">
      <div className="shrink-0 px-5 pt-5 pb-2"><SettingsHeader inputRef={inputRef} /></div>
      <nav aria-label="Settings" className="min-h-0 flex-1 overflow-y-auto px-5 pt-4 pb-5 [&>:last-child]:mb-0">
        {noResult && <NoSearchResult className="ml-2" />}
        {groups.map((group) => {
          const sections = settingsSections.filter((section) => section.group === group && isVisible(section.id));
          if (!sections.length) return null;
          return (
            <div key={group}>
              <h2 className="section-heading settings-heading mb-4 ml-2 text-md font-semibold tracking-normal">{group}</h2>
              <SidebarMenu className="-mt-1 mb-7 gap-0">
                {sections.map((section) => (
                  <SidebarMenuItem key={section.id}>
                    <SidebarMenuButton type="button" isActive={current === section.id} aria-current={current === section.id ? "page" : undefined} onClick={() => jumpTo(section.id)}>
                      {icons[section.id]}
                      {section.title}
                    </SidebarMenuButton>
                  </SidebarMenuItem>
                ))}
              </SidebarMenu>
            </div>
          );
        })}
      </nav>
    </div>
  );
}
