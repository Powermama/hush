// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The post settings panel, docked beside the editor as in Ghost's editor
// (apps/admin/src/editor/settings, MIT, Copyright (c) 2013-2026 Ghost
// Foundation): a rounded panel 350px wide that narrows the writing area above
// 1024px, overlays it below, and takes the whole width on a phone. Its header
// stays put while the sections scroll; rows such as Meta data open a pane over
// the list, which the back button or Escape closes. Ghost's sections for
// members, newsletters, tags and code injection are left out; the article
// contract's fields take their places.
import { blogAuthorIds, blogAuthors } from "@hush/article/authors";
import { blogArticleTypes, blogClusterIds, blogClusters, blogLanguages } from "@hush/article/taxonomy";
import { ArrowLeft, ArrowUpRight, ChevronRight, History, ImageIcon, Keyboard, Link as LinkIcon, Search } from "lucide-react";
import {
  createContext, forwardRef, useCallback, useContext, useEffect, useId, useImperativeHandle, useLayoutEffect, useMemo, useRef, useState,
  type ComponentProps, type CSSProperties, type ReactNode, type Ref,
} from "react";
import type { CreateDraftBody, Post } from "@/api/cms.generated";
import { PostMedia } from "@/components/post-media";
import { PostRevisions } from "@/components/post-revisions";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { InputGroup, InputGroupAddon, InputGroupInput } from "@/components/ui/input-group";
import { Kbd, KbdGroup } from "@/components/ui/kbd";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Separator } from "@/components/ui/separator";
import { Textarea } from "@/components/ui/textarea";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { articleUrl, articleUrlPreview } from "@/lib/article-url";
import { cn } from "@/lib/utils";

/** Every field of a post; the API also takes a draft with fields left out. */
export type PostDraft = Required<CreateDraftBody>;
type Fields = Omit<PostDraft, "markdown">;

/** One block of the panel. */
function SettingsSection({ children }: { children: ReactNode }) {
  return <div className="flex flex-col gap-2 px-5 py-4">{children}</div>;
}

function Hint({ id, children }: { id?: string; children: ReactNode }) {
  return <p id={id} className="text-sm text-text-secondary">{children}</p>;
}

const rowClassName = "flex w-full items-center gap-2 px-5 py-3 text-left text-foreground hover:bg-interactive-hover focus-visible:ring-1 focus-visible:ring-focus-ring focus-visible:outline-hidden [&>svg]:size-4 [&>svg]:shrink-0";

/** A row in the section list that opens its pane. */
const NavigationRow = forwardRef<HTMLButtonElement, ComponentProps<"button"> & { icon: ReactNode }>(function NavigationRow({ icon, children, className, ...props }, ref) {
  return (
    <button ref={ref} type="button" className={cn(rowClassName, className)} {...props}>
      {icon}
      <span className="flex-1 text-control! font-medium">{children}</span>
      <ChevronRight className="size-4 shrink-0 text-text-tertiary" />
    </button>
  );
});

// The panel's one open pane. The panel owns it, so closing the panel drops it.
type PaneId = "history" | "images" | "meta-data" | "keyboard-shortcuts";
type OpenPane = { id: PaneId; title: string };
const PaneContext = createContext<{ open: OpenPane | null; show: (pane: OpenPane) => void; close: () => void } | null>(null);

function usePaneController() {
  const [open, setOpen] = useState<OpenPane | null>(null);
  const close = useCallback(() => {
    // Removing a focused field does not fire blur; blur it first, as the back button does.
    if (document.activeElement instanceof HTMLElement) document.activeElement.blur();
    setOpen(null);
  }, []);
  const show = useCallback((pane: OpenPane) => setOpen(pane), []);
  useEffect(() => {
    if (!open) return;
    // A select inside the pane answers Escape first; Radix marks that by preventing the default.
    const key = (event: KeyboardEvent) => { if (event.key === "Escape" && !event.defaultPrevented) close(); };
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  }, [open, close]);
  return useMemo(() => ({ open, show, close }), [open, show, close]);
}

/** A section that opens a pane over the rest of the panel: its row while closed, the pane with its own header while open. */
function SettingsSubview({ id, icon, label, title, closeLabel, contentClassName, children }: {
  id: PaneId; icon: ReactNode; label: string; title: string; closeLabel: string; contentClassName?: string; children: ReactNode;
}) {
  const panes = useContext(PaneContext)!;
  const isOpen = panes.open?.id === id;
  const back = useRef<HTMLButtonElement>(null);
  const row = useRef<HTMLButtonElement>(null);
  const wasOpen = useRef(false);
  // Opening moves the writer into the pane; closing puts them back on its row.
  useEffect(() => {
    if (isOpen) back.current?.focus();
    else if (wasOpen.current) row.current?.focus();
    wasOpen.current = isOpen;
  }, [isOpen]);

  if (!isOpen) return <NavigationRow ref={row} icon={icon} onClick={() => panes.show({ id, title })}>{label}</NavigationRow>;
  return (
    <>
      <div className="z-10 shrink-0 bg-sidebar">
        <div className="flex items-center gap-2 px-4 py-3">
          <Button ref={back} aria-label={closeLabel} shape="pill" size="icon" variant="ghost" className="hover:bg-sidebar-accent [&_svg]:stroke-2!" onClick={panes.close}>
            <ArrowLeft />
          </Button>
          <h2 className="flex-1 text-lg font-semibold">{title}</h2>
          <div aria-hidden className="size-(--editor-settings-toggle-width) shrink-0" />
        </div>
      </div>
      <div className={cn("flex min-h-0 flex-1 flex-col gap-5 overflow-y-auto px-5 py-4 [&>*]:shrink-0", contentClassName)}>{children}</div>
    </>
  );
}

/** Ghost's countdown, with the range the article contract asks for: green inside it, red outside. */
function Countdown({ id, value, min, max }: { id: string; value: string; min: number; max: number }) {
  const used = Array.from(value).length;
  return (
    <Hint id={id}>
      Recommended: <b>{min}-{max}</b> characters. You&apos;ve used{" "}
      <span className={cn("font-bold", used >= min && used <= max ? "text-character-count" : "text-destructive")}>{used}</span>
    </Hint>
  );
}

function GoogleLogo({ className }: { className?: string }) {
  // Shade's assets/images/google-logo.svg.
  return (
    <svg fill="none" viewBox="0 0 92 31" aria-hidden className={className}>
      <path d="M39.15 15.898c0 4.303-3.378 7.473-7.525 7.473s-7.526-3.17-7.526-7.473c0-4.334 3.38-7.474 7.526-7.474 4.147 0 7.526 3.14 7.526 7.474zm-3.294 0c0-2.69-1.958-4.529-4.231-4.529-2.273 0-4.231 1.84-4.231 4.529 0 2.662 1.958 4.528 4.231 4.528 2.273 0 4.231-1.87 4.231-4.528z" fill="#EA4335" />
      <path d="M55.386 15.898c0 4.303-3.379 7.473-7.526 7.473-4.146 0-7.526-3.17-7.526-7.473 0-4.33 3.38-7.474 7.526-7.474 4.147 0 7.526 3.14 7.526 7.474zm-3.294 0c0-2.69-1.959-4.529-4.232-4.529s-4.231 1.84-4.231 4.529c0 2.662 1.958 4.528 4.231 4.528 2.273 0 4.232-1.87 4.232-4.528z" fill="#FBBC05" />
      <path d="M70.945 8.875v13.418c0 5.52-3.267 7.774-7.13 7.774-3.636 0-5.825-2.423-6.65-4.404l2.868-1.19c.511 1.217 1.763 2.652 3.779 2.652 2.472 0 4.004-1.52 4.004-4.38V21.67h-.115c-.737.906-2.158 1.698-3.95 1.698-3.751 0-7.188-3.255-7.188-7.443 0-4.22 3.437-7.501 7.188-7.501 1.789 0 3.21.792 3.95 1.671h.115V8.88h3.129v-.004zm-2.895 7.05c0-2.632-1.763-4.556-4.005-4.556-2.273 0-4.177 1.924-4.177 4.556 0 2.604 1.904 4.501 4.177 4.501 2.242 0 4.005-1.897 4.005-4.501z" fill="#4285F4" />
      <path d="M76.103 1.01v21.903H72.89V1.011h3.213z" fill="#34A853" />
      <path d="M88.624 18.357l2.558 1.699c-.826 1.216-2.815 3.312-6.251 3.312-4.262 0-7.445-3.282-7.445-7.474 0-4.444 3.21-7.473 7.076-7.473 3.893 0 5.798 3.086 6.42 4.754l.341.85-10.028 4.137c.768 1.5 1.962 2.264 3.636 2.264 1.678 0 2.841-.822 3.693-2.069zm-7.87-2.688l6.703-2.774c-.368-.933-1.478-1.583-2.783-1.583-1.674 0-4.005 1.472-3.92 4.357z" fill="#EA4335" />
      <path d="M11.936 13.953v-3.17h10.726c.105.552.159 1.206.159 1.914 0 2.378-.653 5.32-2.757 7.416-2.046 2.123-4.66 3.255-8.124 3.255-6.42 0-11.818-5.21-11.818-11.605C.122 5.368 5.52.158 11.94.158c3.551 0 6.081 1.389 7.982 3.198l-2.246 2.237c-1.363-1.273-3.21-2.264-5.74-2.264-4.688 0-8.354 3.764-8.354 8.434s3.666 8.434 8.354 8.434c3.041 0 4.773-1.216 5.882-2.322.9-.896 1.492-2.176 1.725-3.925l-7.607.003z" fill="#4285F4" />
    </svg>
  );
}

const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
/** Ellipsis included in the limit, as Ghost truncates a result. */
const truncate = (value: string, limit: number) => {
  const characters = Array.from(value);
  return characters.length > limit - 3 ? `${characters.slice(0, limit - 3).join("")}...` : value;
};

/** The result the post would produce in a search engine, as Ghost previews it. */
function SearchPreview({ url, title, description }: { url: string; title: string; description: string }) {
  const now = new Date();
  return (
    <div className="flex flex-col gap-1 rounded-md border border-border bg-surface-elevated p-5 font-[Arial,sans-serif]">
      <div className="mb-5 flex items-center gap-5">
        <GoogleLogo className="h-5 w-auto shrink-0" />
        <div className="flex h-7 min-w-0 flex-1 items-center justify-end rounded-full bg-muted px-3"><Search className="size-4 text-muted-foreground" /></div>
      </div>
      <p className="truncate text-[14px] leading-[1.3]">{url}</p>
      <p className="text-[20px] leading-[1.3] text-search-result-title">{truncate(title || "(Untitled)", 60)}</p>
      <p className="text-[14px] leading-[22px] text-search-result-description">
        {String(now.getDate()).padStart(2, "0")} {months[now.getMonth()]} {now.getFullYear()} - {description
          ? truncate(description, 149)
          : "Search engines will automatically show a custom preview of content related to the search term here if no custom meta description is set."}
      </p>
    </div>
  );
}

const mac = typeof navigator !== "undefined" && /Mac|iPhone|iPad/.test(navigator.platform);
type Key = { text: string; tooltip?: string; mono?: boolean; plain?: boolean };
const typed = (text: string): Key => ({ text, mono: true });

/** The shortcuts this editor answers to, grouped and drawn as Ghost's reference draws them. */
function shortcutGroups(): { title: string; shortcuts: { label: string; style?: string; keys: Key[] }[] }[] {
  const cmd: Key = mac ? { text: "⌘", tooltip: "Command" } : typed("Ctrl");
  const ctrl: Key = mac ? { text: "⌃", tooltip: "Control" } : typed("Ctrl");
  const alt: Key = mac ? { text: "⌥", tooltip: "Option" } : typed("Alt");
  const shift: Key = mac ? { text: "⇧", tooltip: "Shift" } : typed("Shift");
  const enter: Key = mac ? { text: "↩", tooltip: "Return" } : typed("Enter");
  return [
    {
      title: "Formatting",
      shortcuts: [
        { label: "Bold", style: "font-semibold", keys: [cmd, typed("B")] },
        { label: "Emphasize", style: "italic", keys: [cmd, typed("I")] },
        { label: "Link", style: "text-ghostaccent", keys: [cmd, typed("K")] },
        { label: "Quote", keys: [ctrl, typed("Q")] },
        { label: "H2", keys: [ctrl, alt, typed("2")] },
        { label: "H3", keys: [ctrl, alt, typed("3")] },
      ],
    },
    {
      title: "Editing",
      shortcuts: [
        { label: "Line break", keys: [shift, enter] },
        { label: "Undo", keys: [cmd, typed("Z")] },
        { label: "Redo", keys: [cmd, shift, typed("Z")] },
      ],
    },
    {
      title: "Application",
      shortcuts: [
        { label: "Save", keys: [cmd, typed("S")] },
        { label: "Preview", keys: [cmd, typed("P")] },
        { label: "Publish", keys: [cmd, shift, typed("P")] },
        { label: "Toggle settings", keys: [cmd, typed(".")] },
      ],
    },
    {
      title: "Inserting",
      shortcuts: [
        { label: "Blocks", keys: [typed("/")] },
        { label: "Code block", keys: [typed("```"), enter] },
        { label: "Image", keys: [typed("/image")] },
        { label: "Divider", keys: [typed("---"), { text: "or", mono: true, plain: true }, typed("/div")] },
      ],
    },
  ];
}

function KeyCap({ token }: { token: Key }) {
  const cap = (
    <Kbd
      aria-label={token.tooltip} role={token.tooltip ? "img" : undefined} variant="contrast"
      className={cn(token.mono && "font-mono", token.plain && "bg-transparent", token.tooltip && "pointer-events-auto")}
    >
      {token.text}
    </Kbd>
  );
  if (!token.tooltip) return cap;
  return (
    <Tooltip>
      <TooltipTrigger asChild><span className="inline-flex">{cap}</span></TooltipTrigger>
      <TooltipContent>{token.tooltip}</TooltipContent>
    </Tooltip>
  );
}

function KeyboardShortcuts() {
  const groups = useMemo(shortcutGroups, []);
  return groups.map((group) => (
    <div key={group.title} className="mb-2 flex flex-col gap-2">
      <h3 className="border-b border-border-default pb-2 text-md font-semibold">{group.title}</h3>
      <dl className="m-0">
        {group.shortcuts.map((shortcut) => (
          <div key={shortcut.label} className="-mx-2 flex items-center justify-between gap-2 rounded-md px-2 py-1 hover:bg-interactive-hover">
            <dt className="min-w-0 flex-1 wrap-anywhere"><span className={cn("text-sm", shortcut.style)}>{shortcut.label}</span></dt>
            <dd className="m-0 shrink-0"><KbdGroup>{shortcut.keys.map((token) => <KeyCap key={token.text} token={token} />)}</KbdGroup></dd>
          </div>
        ))}
      </dl>
    </div>
  ));
}

export function PostSettingsSidebar({ fields, onChange, post, heading, markdownMode, onRestored, frameRef, opensInPlace = false }: {
  fields: Fields;
  onChange: (patch: Partial<Fields>) => void;
  /** The saved post: its status, address and history. A new post has none yet. */
  post?: Post;
  /** The title the writer is looking at, which the search preview falls back to. */
  heading: string;
  /** The article is edited as Markdown, whose images are managed here. */
  markdownMode: boolean;
  onRestored: (post: Post) => void | Promise<void>;
  /** The panel's frame, whose width transition the editor waits on before unmounting it. */
  frameRef?: Ref<HTMLDivElement | null>;
  /** The panel opens with the editor, restored as the writer left it, so it is in place without sliding in. */
  opensInPlace?: boolean;
}) {
  const id = useId();
  const own = useRef<HTMLDivElement>(null);
  useImperativeHandle(frameRef, () => own.current!, []);
  // A new element has no earlier style to transition from: it renders closed
  // first, its style is read, and then it takes the editor's progress.
  const [entering, setEntering] = useState(!opensInPlace);
  useLayoutEffect(() => {
    own.current?.getBoundingClientRect();
    setEntering(false);
  }, []);
  const panes = usePaneController();
  const open = panes.open;
  const lang = fields.lang;
  const published = post?.status === "published";
  // The typed text, so a trailing comma survives until the next keyword.
  const [keywordsText, setKeywordsText] = useState(fields.secondaryKeywords.join(", "));

  const sections: { key: string; pane?: PaneId; node: ReactNode }[] = [
    {
      key: "url",
      node: (
        <SettingsSection>
          <div className="flex items-center justify-between gap-2">
            <Label htmlFor={`${id}-slug`}>Post URL</Label>
            {published && (
              <a href={articleUrl(post.lang, post.slug)} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1 text-sm text-text-secondary hover:text-foreground">
                View post<ArrowUpRight className="size-3.5" />
              </a>
            )}
          </div>
          <InputGroup>
            <InputGroupAddon><LinkIcon /></InputGroupAddon>
            <InputGroupInput
              id={`${id}-slug`} value={fields.slug}
              onChange={(event) => onChange({ slug: event.target.value.toLowerCase() })}
              onKeyDown={(event) => { if (event.key === "Enter") event.currentTarget.blur(); }}
            />
          </InputGroup>
          <Hint>{articleUrlPreview(lang, fields.slug)}</Hint>
        </SettingsSection>
      ),
    },
    {
      key: "language",
      node: (
        <SettingsSection>
          <Label htmlFor={`${id}-lang`}>Language</Label>
          <Select value={lang} disabled={published} onValueChange={(value) => onChange({ lang: value as Fields["lang"] })}>
            <SelectTrigger id={`${id}-lang`} className="w-full"><SelectValue /></SelectTrigger>
            <SelectContent>{blogLanguages.map((code) => <SelectItem key={code} value={code}>{code === "en" ? "English" : "Deutsch"}</SelectItem>)}</SelectContent>
          </Select>
          {published && <Hint>Unpublish to change.</Hint>}
        </SettingsSection>
      ),
    },
    {
      key: "topic",
      node: (
        <SettingsSection>
          <Label htmlFor={`${id}-cluster`}>Topic</Label>
          <Select value={fields.cluster} onValueChange={(value) => onChange({ cluster: value as Fields["cluster"] })}>
            <SelectTrigger id={`${id}-cluster`} className="w-full"><SelectValue /></SelectTrigger>
            <SelectContent>{blogClusterIds.map((cluster) => <SelectItem key={cluster} value={cluster}>{blogClusters[cluster][lang]}</SelectItem>)}</SelectContent>
          </Select>
        </SettingsSection>
      ),
    },
    {
      key: "type",
      node: (
        <SettingsSection>
          <Label htmlFor={`${id}-type`}>Type</Label>
          <Select value={fields.type} onValueChange={(value) => onChange({ type: value as Fields["type"] })}>
            <SelectTrigger id={`${id}-type`} className="w-full"><SelectValue /></SelectTrigger>
            <SelectContent>{blogArticleTypes.map((type) => <SelectItem key={type} value={type}>{type}</SelectItem>)}</SelectContent>
          </Select>
        </SettingsSection>
      ),
    },
    {
      key: "author",
      node: (
        <SettingsSection>
          <Label htmlFor={`${id}-author`}>Author</Label>
          <Select value={fields.author} onValueChange={(value) => onChange({ author: value as Fields["author"] })}>
            <SelectTrigger id={`${id}-author`} className="w-full"><SelectValue /></SelectTrigger>
            <SelectContent>{blogAuthorIds.map((author) => <SelectItem key={author} value={author}>{blogAuthors[author].name}</SelectItem>)}</SelectContent>
          </Select>
        </SettingsSection>
      ),
    },
    ...(post ? [{
      key: "history",
      pane: "history" as const,
      node: (
        <SettingsSubview id="history" icon={<History />} label="Post history" title="Post history" closeLabel="Close post history panel" contentClassName="px-3">
          <PostRevisions postId={post.id} onRestored={onRestored} />
        </SettingsSubview>
      ),
    }] : []),
    ...(post && markdownMode ? [{
      key: "images",
      pane: "images" as const,
      node: (
        <SettingsSubview id="images" icon={<ImageIcon />} label="Images" title="Images" closeLabel="Close images panel">
          <PostMedia postId={post.id} slug={fields.slug} />
        </SettingsSubview>
      ),
    }] : []),
    {
      key: "meta-data",
      pane: "meta-data",
      node: (
        <SettingsSubview id="meta-data" icon={<Search />} label="Meta data" title="Meta data" closeLabel="Close meta data panel">
          <div className="flex flex-col gap-2">
            <Label htmlFor={`${id}-title`}>Meta title</Label>
            <Input id={`${id}-title`} aria-describedby={`${id}-title-count`} placeholder={heading} value={fields.title} onChange={(event) => onChange({ title: event.target.value })} />
            <Countdown id={`${id}-title-count`} value={fields.title} min={50} max={60} />
          </div>
          <div className="flex flex-col gap-2">
            <Label htmlFor={`${id}-description`}>Meta description</Label>
            <Textarea id={`${id}-description`} aria-describedby={`${id}-description-count`} rows={3} value={fields.description} onChange={(event) => onChange({ description: event.target.value })} />
            <Countdown id={`${id}-description-count`} value={fields.description} min={140} max={160} />
          </div>
          <div className="flex flex-col gap-2">
            <Label htmlFor={`${id}-keyword`}>Main keyword</Label>
            <Input id={`${id}-keyword`} aria-describedby={`${id}-keyword-hint`} value={fields.keyword} onChange={(event) => onChange({ keyword: event.target.value })} />
            <Hint id={`${id}-keyword-hint`}>One keyword per article and language.</Hint>
          </div>
          <div className="flex flex-col gap-2">
            <Label htmlFor={`${id}-secondary`}>Secondary keywords</Label>
            <Input
              id={`${id}-secondary`} aria-describedby={`${id}-secondary-hint`} value={keywordsText}
              onChange={(event) => {
                setKeywordsText(event.target.value);
                onChange({ secondaryKeywords: event.target.value.split(",").map((keyword) => keyword.trim()).filter(Boolean) });
              }}
            />
            <Hint id={`${id}-secondary-hint`}>Comma-separated, up to 8.</Hint>
          </div>
          <div className="flex flex-col gap-2">
            <Label htmlFor={`${id}-image-alt`}>Cover alt text</Label>
            <Textarea id={`${id}-image-alt`} aria-describedby={`${id}-image-alt-count`} rows={2} value={fields.imageAlt} onChange={(event) => onChange({ imageAlt: event.target.value })} />
            <Countdown id={`${id}-image-alt-count`} value={fields.imageAlt} min={10} max={160} />
          </div>
          <div className="flex flex-col gap-2">
            <p className="text-sm font-medium">Search Engine Result Preview</p>
            <SearchPreview url={articleUrlPreview(lang, fields.slug).split("/").join(" › ")} title={fields.title || heading} description={fields.description} />
          </div>
        </SettingsSubview>
      ),
    },
    {
      key: "keyboard-shortcuts",
      pane: "keyboard-shortcuts",
      node: (
        <SettingsSubview id="keyboard-shortcuts" icon={<Keyboard />} label="Keyboard shortcuts" title="Keyboard shortcuts" closeLabel="Close keyboard shortcuts panel">
          <KeyboardShortcuts />
        </SettingsSubview>
      ),
    },
  ];

  return (
    <PaneContext.Provider value={panes}>
      <div
        ref={own}
        className="absolute inset-y-0 right-0 z-30 w-[calc(var(--editor-settings-progress,1)*var(--editor-settings-width))] overflow-hidden editor-settings-motion-[width] lg:static lg:shrink-0"
        style={entering ? ({ "--editor-settings-progress": 0 } as CSSProperties) : undefined}
      >
        <aside
          aria-label={open?.title ?? "Post settings"}
          className="my-2 mr-2 h-[calc(100%-var(--spacing)*4)] w-[calc(var(--editor-settings-width)-var(--spacing)*2)] overflow-hidden rounded-xl border border-border bg-sidebar max-[500px]:m-0 max-[500px]:h-full max-[500px]:w-(--editor-settings-width) max-[500px]:rounded-none max-[500px]:border-0"
        >
          <div className="flex h-full min-h-0 flex-col opacity-(--editor-settings-progress,1) editor-settings-motion-[opacity]">
            {!open && (
              <div className="z-10 shrink-0 bg-sidebar">
                <div className="flex items-center justify-between gap-2 px-4 py-3 max-[500px]:px-3">
                  <h2 className="pl-1 text-lg font-semibold">Post settings</h2>
                  <div aria-hidden className="size-(--editor-settings-toggle-width) shrink-0" />
                </div>
              </div>
            )}
            <div className={cn("flex min-h-0 flex-1 flex-col", open ? "overflow-hidden" : "overflow-x-hidden overflow-y-auto pb-3 [&>*]:shrink-0")}>
              {sections.map((section, index) => {
                if (open && open.id !== section.pane) return null;
                // The rows that open panes follow a rule, as Post history does in Ghost.
                const firstRow = section.pane && !sections.slice(0, index).some((earlier) => earlier.pane);
                return (
                  <div key={section.key} className={cn(open && "flex min-h-0 flex-1 flex-col")}>
                    {!open && firstRow && <Separator className="my-3" />}
                    {section.node}
                  </div>
                );
              })}
            </div>
          </div>
        </aside>
      </div>
    </PaneContext.Provider>
  );
}
