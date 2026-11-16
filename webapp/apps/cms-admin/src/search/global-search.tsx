// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Ghost Admin's global search (apps/admin/src/global-search:
// global-search-provider.tsx, global-search-modal.tsx, actions-source.ts):
// Cmd/Ctrl+K or the sidebar's "Search site" opens a command palette that finds
// posts by title, address or keyword and offers the appearance switch.
import { useNavigate } from "@tanstack/react-router";
import { Search } from "lucide-react";
import { Fragment, createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import { useListPosts, type Post } from "@/api/cms.generated";
import type { ThemeMode } from "@/components/theme-mode";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList, CommandSeparator } from "@/components/ui/command";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { Kbd } from "@/components/ui/kbd";
import { cn } from "@/lib/utils";
import { settingsSections } from "@/settings/settings-context";
import { compareByStatus, isSearchShortcut, search, searchShortcutLabel, type SearchItem, type SearchResultGroup, type SearchSource } from "./search";

const OpenSearchContext = createContext<(() => void) | null>(null);
const debounceMs = 200;
// Another open dialog (the unsaved-changes prompt, a publish flow) keeps the shortcut.
const openDialog = ':is([role="dialog"], [role="alertdialog"])[data-state="open"]';

function escapeRegExp(text: string) {
  return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/** Underlines each case-insensitive match of the term's words, as Ghost does for the whole term. */
function HighlightedText({ text, term }: { text: string; term: string }) {
  const words = term.trim().split(/\s+/).filter(Boolean);
  if (!words.length) return text;
  const pattern = new RegExp(`(${words.map(escapeRegExp).join("|")})`, "gi");
  return text.split(pattern).map((part, index) => index % 2 === 1
    ? <mark key={index} className="bg-transparent font-semibold text-inherit underline">{part}</mark>
    : <Fragment key={index}>{part}</Fragment>);
}

const statusBadges: Record<string, { label: string; tone: string }> = {
  draft: { label: "Draft", tone: "bg-pink/10 text-pink" },
  scheduled: { label: "Scheduled", tone: "bg-green/10 text-green" },
};

function StatusBadge({ status }: { status?: string }) {
  const badge = status ? statusBadges[status] : undefined;
  return badge ? <Badge className={cn("border-transparent", badge.tone)}>{badge.label}</Badge> : null;
}

const optionValue = (group: SearchResultGroup, item: SearchItem) => `${group.id}:${item.id}`;

function useDebounced<T>(value: T, ms: number) {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const timer = setTimeout(() => setDebounced(value), ms);
    return () => clearTimeout(timer);
  }, [value, ms]);
  return debounced;
}

type Appearance = { mode: ThemeMode; setMode: (mode: ThemeMode) => void };

/** The search itself; inside the dialog, so the post list loads only once someone searches. */
function GlobalSearchPanel({ onClose, appearance }: { onClose: () => void; appearance: Appearance }) {
  const [term, setTerm] = useState("");
  const debouncedTerm = useDebounced(term, debounceMs);
  const hasTerm = term.trim() !== "";
  const posts = useListPosts(undefined, { query: { enabled: hasTerm } });
  const navigate = useNavigate();

  const dark = appearance.mode === "dark" || (appearance.mode === "system" && window.matchMedia("(prefers-color-scheme: dark)").matches);
  const sources = useMemo<SearchSource[]>(() => {
    const list: Post[] = posts.data?.status === 200 ? posts.data.data.posts : [];
    return [
      {
        id: "posts", heading: "Posts", compare: compareByStatus,
        items: list.map((post) => ({
          kind: "navigate", id: post.id, title: post.title || "(Untitled)", status: post.status,
          keywords: [post.slug, post.keyword, ...post.secondaryKeywords, post.lang === "de" ? "german deutsch" : "english"].join(" "),
          to: "/posts/$id", params: { id: post.id },
        })),
      },
      // As Ghost's settings/search-source.ts: each settings section opens Settings at it.
      {
        id: "settings", heading: "Settings",
        items: settingsSections.map((section) => ({
          kind: "navigate" as const, id: section.id, title: section.title, keywords: `settings ${section.keywords.join(" ")}`,
          to: "/settings/{-$section}", params: { section: section.id },
        })),
      },
      {
        id: "actions", heading: "Actions",
        items: [{
          kind: "action", id: dark ? "appearance-light" : "appearance-dark", title: dark ? "Switch to light mode" : "Switch to dark mode",
          keywords: "appearance toggle dark light night mode", run: () => appearance.setMode(dark ? "light" : "dark"),
        }],
      },
    ];
  }, [posts.data, dark, appearance]);
  const results = useMemo(() => search(sources, debouncedTerm), [sources, debouncedTerm]);
  const isLoading = hasTerm && (posts.isLoading || term !== debouncedTerm);

  // Each new set of results selects its first option, so Enter opens it.
  const firstValue = results[0] ? optionValue(results[0], results[0].items[0]!) : "";
  const [selected, setSelected] = useState({ results, value: firstValue });
  if (selected.results !== results) setSelected({ results, value: firstValue });

  const openItem = (item: SearchItem) => {
    onClose();
    if (item.kind === "action") item.run();
    else void navigate({ to: item.to, params: item.params });
  };

  return (
    <Command
      className={cn("sm:rounded-lg", !hasTerm && "[&_[cmdk-input-wrapper]]:border-b-0")}
      shouldFilter={false}
      value={selected.value}
      onValueChange={(value) => setSelected({ results, value })}
    >
      <CommandInput placeholder="Search site" value={term} onValueChange={setTerm} />
      <CommandList className={cn("max-h-[50vh]", !hasTerm && "hidden")}>
        {results.map((group, index) => (
          <Fragment key={group.id}>
            {index > 0 && <CommandSeparator alwaysRender />}
            <CommandGroup className="[&_[cmdk-group-heading]]:tracking-wide [&_[cmdk-group-heading]]:uppercase" heading={group.heading}>
              {group.items.map((item) => (
                <CommandItem key={item.id} className="justify-between" value={optionValue(group, item)} onSelect={() => openItem(item)}>
                  <span className="truncate"><HighlightedText term={term} text={item.title} /></span>
                  <StatusBadge status={item.status} />
                </CommandItem>
              ))}
            </CommandGroup>
          </Fragment>
        ))}
        {hasTerm && results.length === 0 && <CommandEmpty>{isLoading ? "Loading" : "No results found"}</CommandEmpty>}
      </CommandList>
    </Command>
  );
}

/** Owns the search modal: its open state and the Cmd/Ctrl+K shortcut. */
export function GlobalSearchProvider({ children, appearance }: { children: ReactNode; appearance: Appearance }) {
  // `count` remounts the panel on each open, so it starts with an empty term.
  const [modal, setModal] = useState({ open: false, count: 0 });
  const openSearch = useCallback(() => setModal((current) => (current.open ? current : { open: true, count: current.count + 1 })), []);
  const setOpen = useCallback((open: boolean) => setModal((current) => ({ ...current, open })), []);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (!isSearchShortcut(event)) return;
      if (!modal.open && document.querySelector(openDialog)) return;
      event.preventDefault();
      openSearch();
    };
    document.addEventListener("keydown", onKeyDown);
    return () => document.removeEventListener("keydown", onKeyDown);
  }, [modal.open, openSearch]);

  return (
    <OpenSearchContext.Provider value={openSearch}>
      {children}
      {modal.count > 0 && (
        <Dialog open={modal.open} onOpenChange={setOpen}>
          <DialogContent aria-describedby={undefined} className="gap-0 p-0">
            <DialogTitle className="sr-only">Search site</DialogTitle>
            <GlobalSearchPanel key={modal.count} onClose={() => setOpen(false)} appearance={appearance} />
          </DialogContent>
        </Dialog>
      )}
    </OpenSearchContext.Provider>
  );
}

/** "Search site" at the top of the sidebar, as Ghost's app-sidebar-header.tsx. */
export function SearchButton() {
  const openSearch = useContext(OpenSearchContext);
  return (
    <Button
      className="flex h-(--control-height) items-center justify-between rounded-full border-transparent bg-white pr-2 text-base text-muted-foreground shadow-xs hover:bg-background hover:text-gray-700 hover:shadow-sm dark:border-gray-900/50 dark:bg-gray-900/30 dark:hover:border-gray-900/80 dark:hover:text-gray-400 [&_svg]:stroke-2"
      variant="outline"
      onClick={openSearch ?? undefined}
    >
      <div className="flex items-center gap-2">
        <Search className="text-muted-foreground" />
        Search site
      </div>
      <Kbd className="bg-transparent text-gray-500 shadow-none dark:text-gray-800" style={{ textShadow: "none" }}>{searchShortcutLabel}</Kbd>
    </Button>
  );
}
