// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Writing a post, as in Ghost's editor (apps/admin/src/editor): the title, an
// excerpt and the article's blocks on a quiet page, a floating header with the
// way back, the status and the actions, and the word count in the corner. A
// draft saves itself while its author writes; a live post changes only with
// "Update". The article stays Markdown: blocks are read from it and written
// back (@hush/article/blocks), and Markdown that blocks cannot hold exactly is
// edited as Markdown. The post's settings dock beside it (Cmd/Ctrl+.), and
// publishing ends on the posts list, which celebrates the post, as in Ghost.
import { readArticle, writeArticle } from "@hush/article/blocks";
import { tldrTitles } from "@hush/article/markdown";
import { useQueryClient } from "@tanstack/react-query";
import { Link, useBlocker, useNavigate } from "@tanstack/react-router";
import { ArrowLeft, PanelRight } from "lucide-react";
import {
  useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type CSSProperties, type KeyboardEvent, type RefObject,
} from "react";
import { toast } from "sonner";
import {
  approvePost, createDraft, getGetPostQueryKey, getListMediaQueryKey, getListPostsQueryKey, getListRevisionsQueryKey, previewPost, publishPost,
  schedulePost, unpublishPost, updatePost, uploadMedia, useListMedia, type Media, type Post, type Preview,
} from "@/api/cms.generated";
import { CmsError } from "@/api/fetcher";
import { MarkdownEditor } from "@/components/markdown-editor";
import { writePublishCelebration } from "@/components/publish-celebration";
import { PostSettingsSidebar, type PostDraft } from "@/components/post-settings";
import { PostPreview } from "@/components/post-preview";
import { PublishFlow, type Refusal } from "@/components/publish-flow";
import { useSettingsOpen } from "@/components/settings-open";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { Button } from "@/components/ui/button";
import { ArticleEditor } from "@/editor/article-editor";
import { EditorHostContext, type EditorHost } from "@/editor/host";
import type { ArticleEditorHandle } from "@/editor/plugins";
import { articleUrl } from "@/lib/article-url";
import { cn } from "@/lib/utils";
import { useShade } from "@/providers/shade-context";

type Fields = Omit<PostDraft, "markdown">;

const emptyFields: Fields = {
  lang: "en", slug: "", title: "", description: "", keyword: "", secondaryKeywords: [],
  type: "how-to", cluster: "local-dictation", author: "clemens-kressmann", imageAlt: "",
};

const fieldsOf = (post: Post): Fields => ({
  lang: post.lang, slug: post.slug, title: post.title, description: post.description, keyword: post.keyword,
  secondaryKeywords: post.secondaryKeywords, type: post.type, cluster: post.cluster, author: post.author, imageAlt: post.imageAlt,
});

/** The CMS's message and the contract's problems, for a toast and the problems list. */
function describe(error: unknown) {
  return error instanceof CmsError ? { message: error.message, problems: error.problems } : { message: "Something went wrong.", problems: [] };
}

/** A lowercase, dash-separated name the CMS accepts, keeping the extension. */
function mediaName(file: File) {
  const extension = file.type === "image/jpeg" ? "jpg" : file.type === "image/webp" ? "webp" : "png";
  const base = file.name.replace(/\.[^.]+$/, "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "") || "image";
  return `${base}.${extension}`;
}

const fieldClass = "block w-full max-w-none min-w-0 min-h-0 resize-none overflow-hidden border-0 bg-transparent p-0 outline-none";
const pill = "inline-flex h-(--control-height) items-center rounded-full bg-background/80 px-3 text-control font-medium text-text-secondary backdrop-blur-sm";
const headerButton = "bg-background/80 backdrop-blur-sm";
const emphasis = "font-semibold text-publish-accent hover:text-publish-accent disabled:text-text-secondary/60";

/** A textarea as tall as its text, also when its column narrows beside the settings panel. */
function useAutosize(ref: RefObject<HTMLTextAreaElement | null>, value: string) {
  useLayoutEffect(() => {
    const element = ref.current;
    if (!element) return;
    const fit = () => { element.style.height = "auto"; element.style.height = `${element.scrollHeight}px`; };
    fit();
    // Only a new width rewraps the text; the height this sets must not start another fit.
    let width = element.clientWidth;
    const observer = new ResizeObserver(() => {
      if (element.clientWidth === width) return;
      width = element.clientWidth;
      fit();
    });
    observer.observe(element);
    return () => observer.disconnect();
  }, [ref, value]);
}

/** CSS transitions running on an element (or inside it); WebKit before 17 knows no CSSTransition. */
function transitionsOf(element: Element | null, subtree = false) {
  if (!element || typeof CSSTransition === "undefined") return [];
  return element.getAnimations({ subtree }).filter((animation) => animation instanceof CSSTransition);
}

type SaveState = "idle" | "saving" | "error";

export function PostEditor({ post, onCreated, onReopen }: { post?: Post; onCreated?: (id: string) => void; onReopen?: () => void }) {
  const queryClient = useQueryClient();
  const { darkMode } = useShade();

  // What the article was when the editor opened decides how it is edited.
  const opened = useMemo(() => {
    const read = readArticle(post?.markdown ?? "");
    return read.article ? { article: read.article } : { reason: read.unsupported, markdown: post?.markdown ?? "" };
    // The editor keeps its own text; a post is opened once.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const [fields, setFields] = useState<Fields>(() => (post ? fieldsOf(post) : emptyFields));
  const [heading, setHeading] = useState(opened.article?.title ?? "");
  const [markdown, setMarkdown] = useState(opened.markdown ?? "");
  const [saveState, setSaveState] = useState<SaveState>("idle");
  const [saveError, setSaveError] = useState("");
  const [dirty, setDirty] = useState(false);
  const [updated, setUpdated] = useState(false);
  const [busy, setBusy] = useState(false);
  const [words, setWords] = useState({ all: 0, selected: 0 });
  const [typing, setTyping] = useState(false);
  const [showPreview, setShowPreview] = useState(false);
  const [publishOpen, setPublishOpen] = useState(false);
  const [preview, setPreview] = useState<Preview | null>(null);
  const navigate = useNavigate();

  // The settings panel opens as the writer last left it; restored open, it is in place from the first paint.
  const settingsMemory = useSettingsOpen();
  const [settingsOpen, setSettingsOpen] = useState(settingsMemory.openAtStart);
  // Mounted from the toggle until its closing transition has ended.
  const [settingsPresent, setSettingsPresent] = useState(settingsMemory.openAtStart);
  // From a toggle until everything moving with the panel has arrived; the chrome stays meanwhile.
  const [settingsMoving, setSettingsMoving] = useState(false);
  const shellRef = useRef<HTMLDivElement>(null);
  const settingsFrameRef = useRef<HTMLDivElement>(null);
  const settingsToggleRef = useRef<HTMLButtonElement>(null);
  const [problems, setProblems] = useState<string[]>([]);

  const editor = useRef<ArticleEditorHandle>(null);
  const titleRef = useRef<HTMLTextAreaElement>(null);
  const excerptRef = useRef<HTMLTextAreaElement>(null);
  useAutosize(titleRef, heading);
  useAutosize(excerptRef, fields.description);

  // The latest of everything, for saves that run from timers and events.
  const current = useRef({ post, fields, heading, markdown });
  current.current = { post, fields, heading, markdown };
  // Each change counts up; a save knows which change it covered.
  const changes = useRef({ content: 0, fields: 0, savedContent: 0, savedFields: 0 });
  const saving = useRef<Promise<string | undefined> | null>(null);
  // Why the last save was refused, for the publish flow to show.
  const lastRefusal = useRef<Refusal | undefined>(undefined);
  // The post this editor created, until the route hands it back as `post`.
  const created = useRef<Post | undefined>(undefined);
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const dirtySince = useRef<number | null>(null);
  const autosaveRef = useRef<() => void>(() => {});
  const live = post?.status === "published" || post?.status === "scheduled";

  const refresh = useCallback(async (id: string) => {
    await Promise.all([
      queryClient.invalidateQueries({ queryKey: getListPostsQueryKey() }),
      queryClient.invalidateQueries({ queryKey: getListRevisionsQueryKey(id) }),
    ]);
  }, [queryClient]);

  /** The article as Markdown: written from the blocks only once the author changed them. */
  const articleMarkdown = useCallback(() => {
    const { post: saved, heading: title, markdown: text } = current.current;
    if (!opened.article) return text;
    if (changes.current.content === 0) return saved?.markdown ?? "";
    return writeArticle({ title, blocks: editor.current?.blocks() ?? [] });
  }, [opened]);

  /** Takes over what the CMS stored, including a slug it chose (images follow it, as on the server). */
  const adopt = useCallback((stored: Post, previousSlug: string) => {
    queryClient.setQueryData(getGetPostQueryKey(stored.id), { data: stored, status: 200, headers: new Headers() });
    if (stored.slug !== previousSlug) {
      if (previousSlug) editor.current?.moveImages(previousSlug, stored.slug);
      setFields((value) => (value.slug === previousSlug ? { ...value, slug: stored.slug } : value));
    }
  }, [queryClient]);

  /** Saves what changed; returns the post id, or undefined when the CMS refused it. One save runs at a time. */
  const save = useCallback(async (kind: "auto" | "manual" = "manual"): Promise<string | undefined> => {
    if (saving.current) {
      await saving.current;
      // What was typed meanwhile still needs saving.
      if (changes.current.content === changes.current.savedContent && changes.current.fields === changes.current.savedFields) return current.current.post?.id;
      return save(kind);
    }
    const run = (async () => {
      clearTimeout(timer.current);
      const { fields: draft } = current.current;
      const saved = current.current.post ?? created.current;
      const covered = { content: changes.current.content, fields: changes.current.fields };
      const text = articleMarkdown();
      setSaveState("saving");
      const started = Date.now();
      try {
        let stored: Post;
        if (!saved) {
          // A new draft is named by the CMS after its heading unless its author chose a slug.
          const { slug, ...rest } = draft;
          stored = (await createDraft({ ...rest, ...(slug ? { slug } : {}), markdown: text })).data as Post;
          created.current = stored;
          adopt(stored, slug);
          onCreated?.(stored.id);
        } else {
          const before: PostDraft = { ...fieldsOf(saved), markdown: saved.markdown };
          const after: PostDraft = { ...draft, markdown: text };
          const patch = Object.fromEntries(Object.entries(after).filter(([key, value]) => JSON.stringify(value) !== JSON.stringify(before[key as keyof PostDraft])));
          if (!Object.keys(patch).length) { setSaveState("idle"); return saved.id; }
          stored = (await updatePost(saved.id, patch, kind === "auto" ? { autosave: "true" } : undefined)).data as Post;
          if (created.current) created.current = stored;
          adopt(stored, saved.slug);
        }
        changes.current.savedContent = covered.content;
        changes.current.savedFields = covered.fields;
        const clean = changes.current.content === covered.content && changes.current.fields === covered.fields;
        if (clean) dirtySince.current = null;
        setDirty(!clean);
        setProblems([]);
        setSaveError("");
        void refresh(stored.id);
        // "Saving…" stays long enough to be read, as in Ghost.
        if (kind === "auto") await new Promise((resolve) => setTimeout(resolve, Math.max(0, 1000 - (Date.now() - started))));
        setSaveState("idle");
        if (!clean) autosaveRef.current();
        return stored.id;
      } catch (error) {
        const { message, problems: refused } = describe(error);
        lastRefusal.current = { message, problems: refused };
        setProblems(refused);
        setSaveError(message);
        setSaveState("error");
        if (kind === "manual") toast.error(message);
        return undefined;
      }
    })();
    saving.current = run;
    try { return await run; } finally { saving.current = null; }
  }, [articleMarkdown, adopt, onCreated, refresh]);

  /** A draft saves three seconds after its author stops, and once a minute while they keep writing. */
  const autosave = useCallback(() => {
    const status = current.current.post?.status;
    if (status === "published" || status === "scheduled") return;
    clearTimeout(timer.current);
    dirtySince.current ??= Date.now();
    const wait = Date.now() - dirtySince.current > 60_000 ? 0 : 3000;
    timer.current = setTimeout(() => void save("auto"), wait);
  }, [save]);
  autosaveRef.current = autosave;
  useEffect(() => () => clearTimeout(timer.current), []);

  const changedContent = useCallback(() => { changes.current.content++; setDirty(true); setUpdated(false); autosave(); }, [autosave]);
  const changedFields = useCallback((patch: Partial<Fields>) => {
    setFields((value) => ({ ...value, ...patch }));
    changes.current.fields++;
    setDirty(true);
    setUpdated(false);
    autosave();
  }, [autosave]);

  const onWords = useCallback((all: number, selected: number) => setWords({ all, selected }), []);
  const onTyping = useCallback(() => setTyping(true), []);
  const onLeaveUp = useCallback(() => {
    const field = fields.description || excerptRef.current ? excerptRef.current : titleRef.current;
    field?.focus();
    field?.setSelectionRange(field.value.length, field.value.length);
  }, [fields.description]);

  // The chrome comes back when the pointer moves, as in Ghost.
  useEffect(() => {
    if (!typing) return;
    let from: { x: number; y: number } | null = null;
    const move = (event: MouseEvent) => {
      from ??= { x: event.clientX, y: event.clientY };
      if (Math.hypot(event.clientX - from.x, event.clientY - from.y) > 10) setTyping(false);
    };
    window.addEventListener("mousemove", move);
    return () => window.removeEventListener("mousemove", move);
  }, [typing]);
  // The chrome stays while the settings panel is out or moving.
  const writingFocus = typing && !settingsOpen && !settingsMoving ? "hidden" : "visible";

  // Keep the panel mounted until its closing transition ends; a reopen cancels the wait.
  useLayoutEffect(() => {
    if (settingsOpen || !settingsPresent) return;
    const transitions = transitionsOf(settingsFrameRef.current);
    if (!transitions.length) { setSettingsPresent(false); return; }
    let cancelled = false;
    void Promise.allSettled(transitions.map((transition) => transition.finished)).then(() => { if (!cancelled) setSettingsPresent(false); });
    return () => { cancelled = true; };
  }, [settingsOpen, settingsPresent]);
  // Reading the shell's transitions also flushes the style that starts them.
  useLayoutEffect(() => {
    if (!settingsMoving) return;
    const transitions = transitionsOf(shellRef.current, true);
    let cancelled = false;
    void Promise.allSettled(transitions.map((transition) => transition.finished)).then(() => { if (!cancelled) setSettingsMoving(false); });
    return () => { cancelled = true; };
  }, [settingsOpen, settingsMoving]);

  const { toggled: settingsToggled } = settingsMemory;
  const flipSettings = useCallback(() => {
    setSettingsMoving(true);
    setSettingsPresent(true);
    // Only the writer's own toggle is remembered.
    settingsToggled(!settingsOpen);
    setSettingsOpen((open) => !open);
  }, [settingsOpen, settingsToggled]);

  // Cmd/Ctrl+. opens and closes the settings, as in Ghost (use-editor-shortcuts.ts). It leaves focus
  // where the writer is typing, unless closing the panel takes it away: then it lands on the toggle.
  // Nothing happens while the publish flow, the preview or another modal is open.
  const blockerRef = useRef(false);
  const settingsShortcut = useRef(() => {});
  settingsShortcut.current = () => {
    if (publishOpen || showPreview || blockerRef.current || shellRef.current?.closest("[aria-hidden=true]")) return;
    if (settingsOpen && settingsFrameRef.current?.contains(document.activeElement)) settingsToggleRef.current?.focus();
    flipSettings();
  };
  useEffect(() => {
    const key = (event: globalThis.KeyboardEvent) => {
      // Autofill sends keydown events without a key.
      if (typeof event.key !== "string" || event.key !== "." || !(event.metaKey || event.ctrlKey) || event.altKey || event.shiftKey) return;
      event.preventDefault();
      if (!event.repeat) settingsShortcut.current();
    };
    document.addEventListener("keydown", key);
    return () => document.removeEventListener("keydown", key);
  }, []);

  // Cmd/Ctrl+S saves at once, whatever has the focus.
  useEffect(() => {
    const key = (event: globalThis.KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.shiftKey && !event.altKey && event.key.toLowerCase() === "p" && current.current.post?.status === "draft") {
        event.preventDefault();
        setShowPreview(false);
        setPublishOpen(true);
        return;
      }
      if ((event.metaKey || event.ctrlKey) && !event.shiftKey && !event.altKey && event.key.toLowerCase() === "p" && current.current.post?.status === "draft") {
        event.preventDefault();
        setShowPreview((value) => !value);
        return;
      }
      if ((event.metaKey || event.ctrlKey) && !event.shiftKey && !event.altKey && event.key.toLowerCase() === "s") {
        event.preventDefault();
        void save("manual").then((id) => { if (id && current.current.post && current.current.post.status !== "draft") setUpdated(true); });
      }
    };
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  }, [save]);

  // Leaving with unsaved work: closing the tab asks; going elsewhere in the admin saves first.
  useEffect(() => {
    if (!dirty) return;
    const warn = (event: BeforeUnloadEvent) => { event.preventDefault(); };
    window.addEventListener("beforeunload", warn);
    return () => window.removeEventListener("beforeunload", warn);
  }, [dirty]);
  const blocker = useBlocker({
    shouldBlockFn: async ({ next }) => {
      // Moving from "new" to the saved post's own address is not leaving.
      if (created.current && next.pathname === `/posts/${created.current.id}`) return false;
      const unsaved = changes.current.content !== changes.current.savedContent || changes.current.fields !== changes.current.savedFields;
      if (!unsaved) return false;
      // A draft saves on the way out; only what cannot be saved asks first.
      const status = (current.current.post ?? created.current)?.status;
      if (!status || status === "draft") return !(await save("manual"));
      return true;
    },
    withResolver: true,
    enableBeforeUnload: false,
  });
  blockerRef.current = blocker.status === "blocked";

  const host = useRef<Omit<EditorHost, "mediaLoaded">>(null!);
  const media = useListMedia(post?.id ?? "", { query: { enabled: Boolean(post) } });
  const stored: Media[] = media.data?.data && "media" in media.data.data ? media.data.data.media : [];
  host.current = {
    upload: async (file) => {
      const id = await save("manual");
      if (!id) return undefined;
      try {
        const name = mediaName(file);
        await uploadMedia(id, name, file, { headers: { "Content-Type": file.type } });
        await queryClient.invalidateQueries({ queryKey: getListMediaQueryKey(id) });
        return `media/${(current.current.post ?? created.current)?.slug}/${name}`;
      } catch (error) {
        toast.error(error instanceof CmsError ? error.message : "The upload failed.");
        return undefined;
      }
    },
    imageUrl: (src) => {
      const image = stored.find((item) => item.name === src.split("/").at(-1));
      return image && `/v1/media/${image.sha256}`;
    },
  };
  // One object for the editor's life; it always asks the latest state.
  // A new value whenever the stored images change, so the image cards draw again once the list arrives.
  const mediaLoaded = !post || media.isSuccess;
  const hostValue = useMemo<EditorHost>(
    () => ({ upload: (file) => host.current.upload(file), imageUrl: (src) => host.current.imageUrl(src), mediaLoaded }),
    // media.data is the stored list as the query last read it.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [media.data, mediaLoaded],
  );

  /**
   * Approves the draft as previewed, after saving it, so an agent may schedule
   * or publish it as it is. The CMS refuses if it changed since this editor
   * last read it, so nothing is approved unseen.
   */
  const approve = async () => {
    setBusy(true);
    try {
      const id = await save("manual");
      if (!id) return void toast.error(lastRefusal.current?.message ?? "The post could not be saved.");
      const reviewed = (queryClient.getQueryData(getGetPostQueryKey(id)) as { data: Post } | undefined)?.data;
      if (!reviewed) return;
      const stored = (await approvePost(id, { contentHash: reviewed.contentHash })).data as Post;
      queryClient.setQueryData(getGetPostQueryKey(id), { data: stored, status: 200, headers: new Headers() });
      await refresh(id);
      toast.success("Approved. An agent may now schedule or publish it as it is.");
    } catch (error) {
      toast.error(describe(error).message);
    } finally {
      setBusy(false);
    }
  };

  /** Publishes, schedules or reverts to a draft after saving; answers with what was refused, for the flow to show. */
  const act = async (action: "publish" | "unpublish" | { scheduleAt: Date }): Promise<Refusal | undefined> => {
    setBusy(true);
    try {
      const id = await save("manual");
      if (!id) return lastRefusal.current ?? { message: "The post could not be saved.", problems: [] };
      const result = action === "publish" ? await publishPost(id)
        : action === "unpublish" ? await unpublishPost(id)
          : await schedulePost(id, { publishedAt: action.scheduleAt.toISOString() });
      const stored = result.data as Post;
      queryClient.setQueryData(getGetPostQueryKey(id), { data: stored, status: 200, headers: new Headers() });
      setProblems([]);
      await refresh(id);
      if (action === "unpublish") {
        toast.success("Post reverted to a draft.");
      } else {
        // As in Ghost, a publish or schedule hands the celebration to the posts list and goes there;
        // the flow stays on its running button until the editor unmounts.
        writePublishCelebration({ id, scheduled: action !== "publish" });
        void navigate({ to: "/", search: {} });
      }
      return undefined;
    } catch (error) {
      const refusal = describe(error);
      setProblems(refusal.problems);
      return refusal;
    } finally {
      setBusy(false);
    }
  };

  // The preview: rendered by the CMS a moment after the last change, with the contract's problems.
  const latest = useRef(0);
  useEffect(() => {
    if (!post || !showPreview) { setPreview(null); return; }
    const request = ++latest.current;
    const wait = setTimeout(async () => {
      try {
        const result = await previewPost(post.id, { ...current.current.fields, markdown: articleMarkdown() });
        if (request === latest.current) setPreview(result.data as Preview);
      } catch (error) {
        const { message, problems: refused } = describe(error);
        if (request === latest.current) setPreview({ problems: refused.length ? refused : [message], rendition: null });
      }
    }, 600);
    return () => clearTimeout(wait);
  }, [post, showPreview, fields, heading, markdown, words.all, articleMarkdown]);
  const shownProblems = useMemo(() => [...new Set([...problems, ...(preview?.problems ?? [])])], [problems, preview]);

  const titleKey = (event: KeyboardEvent<HTMLTextAreaElement>) => {
    const end = event.currentTarget.selectionStart === event.currentTarget.value.length;
    if (event.key === "Enter" || event.key === "Tab" && !event.shiftKey || (event.key === "ArrowDown" || event.key === "ArrowRight") && end) {
      event.preventDefault();
      excerptRef.current?.focus();
      excerptRef.current?.setSelectionRange(0, 0);
    }
  };
  const excerptKey = (event: KeyboardEvent<HTMLTextAreaElement>) => {
    const { selectionStart, value } = event.currentTarget;
    if (event.key === "Enter" || event.key === "Tab" && !event.shiftKey || (event.key === "ArrowDown" || event.key === "ArrowRight") && selectionStart === value.length) {
      event.preventDefault();
      editor.current?.focus();
    } else if ((event.key === "ArrowUp" || event.key === "ArrowLeft") && selectionStart === 0 || event.key === "Tab" && event.shiftKey) {
      event.preventDefault();
      titleRef.current?.focus();
    }
  };

  const status = (() => {
    if (saveState === "error") {
      return <span className="text-destructive">{saveError || "Could not save."} <Button variant="link" className="h-auto p-0 text-destructive underline underline-offset-4" onClick={() => void save("manual")}>Retry</Button></span>;
    }
    if (saveState === "saving" && !live) return "Saving…";
    if (!post) return dirty ? "New" : "";
    if (post.status === "published") return <a href={articleUrl(post.lang, post.slug)} target="_blank" rel="noreferrer" className="hover:text-foreground">Published</a>;
    if (post.status === "scheduled") return <span className="text-state-success">Scheduled</span>;
    return dirty ? "Draft" : "Draft - Saved";
  })();

  return (
    <EditorHostContext.Provider value={hostValue}>
      <div
        className="relative flex h-dvh min-h-0 flex-col bg-background"
        // Hidden controls stay focusable; focusing one brings the chrome back.
        onFocus={(event) => { if ((event.target as HTMLElement).closest("[data-writing-focus]")) setTyping(false); }}
      >
        {/* The editor and its settings panel side by side, as Ghost's editor screen lays them out. */}
        <div
          ref={shellRef}
          className="relative flex min-h-0 flex-1 items-stretch [--editor-overlap:65px] [--editor-settings-width:350px] max-[500px]:[--editor-overlap:56px] max-[500px]:[--editor-settings-width:100vw]"
          style={{
            // Never animated: what moves with the panel transitions its own property.
            "--editor-settings-progress": settingsOpen ? 1 : 0,
            "--editor-settings-toggle-width": "var(--control-height)",
          } as CSSProperties}
        >
          <div className="relative flex min-h-0 min-w-0 flex-1 flex-col">
            <header className="pointer-events-none relative z-20 grid shrink-0 grid-cols-[auto_minmax(0,1fr)_auto] items-start gap-2 pt-[calc(var(--spacing)*5+1px)] pr-[calc(var(--spacing)*(4+2*var(--editor-settings-progress,0)))] pb-3 pl-4 editor-settings-motion-[padding-right] max-[500px]:pt-3 max-[500px]:pr-[calc(var(--spacing)*(1+2*var(--editor-settings-progress,0))-1px)] max-[500px]:pl-3 [&_a]:pointer-events-auto [&_button]:pointer-events-auto">
              {/* The way out stays while the writer types. */}
              <Button asChild size="icon" variant="ghost" className={headerButton}>
                <Link to="/" search={{}} aria-label="Posts"><ArrowLeft className="stroke-2!" /></Link>
              </Button>
              <div className="min-w-0" data-writing-focus={writingFocus}>
                {status && <span aria-live="polite" className={cn(pill, "pointer-events-auto inline-block max-w-full truncate align-top leading-(--control-height)")}>{status}</span>}
              </div>
              <div className="col-start-3 ml-auto" data-writing-focus={writingFocus}>
                <div className="flex items-center gap-x-[calc(var(--spacing)*3*(1-var(--editor-settings-progress)))] editor-settings-motion-[column-gap] max-[500px]:gap-x-[calc(var(--spacing)*(1-var(--editor-settings-progress)))]">
                  {/* As in Ghost, a draft is previewed; a live post is on behu.sh. */}
                  {post?.status === "draft" && (
                    <Button variant="ghost" className={headerButton} aria-pressed={showPreview} onClick={() => setShowPreview((value) => !value)}>Preview</Button>
                  )}
                  {live && (
                    <Button variant="ghost" className={headerButton} disabled={busy} onClick={() => setPublishOpen(true)}>
                      {post?.status === "scheduled" ? "Unschedule" : "Unpublish"}
                    </Button>
                  )}
                  {live && (
                    <Button
                      variant="ghost" className={cn(headerButton, emphasis)} disabled={busy || saveState === "saving" || (!dirty && !updated)}
                      onClick={() => void save("manual").then((id) => { if (id) { setUpdated(true); setTimeout(() => setUpdated(false), 2500); } })}
                    >
                      {saveState === "saving" ? "Updating..." : saveState === "error" ? "Retry" : updated ? "Updated" : "Update"}
                    </Button>
                  )}
                  {post?.status === "draft" && (
                    <Button variant="ghost" className={cn(headerButton, emphasis)} disabled={busy} onClick={() => setPublishOpen(true)}>Publish</Button>
                  )}
                  {/* The settings toggle floats over this place; it moves into the panel's header when the panel opens. */}
                  <div aria-hidden className="w-[calc((var(--editor-settings-toggle-width)+var(--spacing)*2+1px)*(1-var(--editor-settings-progress)))] shrink-0 editor-settings-motion-[width]" />
                </div>
              </div>
            </header>

            <div className="relative isolate min-h-0 flex-1">
              <div className="editor-optical-sizing -mt-(--editor-overlap) h-[calc(100%+var(--editor-overlap))] min-h-0 overflow-x-hidden overflow-y-auto scroll-pt-(--editor-overlap)">
                <div
                  className="flex min-h-full flex-col px-6 pt-[calc(48px+var(--editor-overlap))] pb-24 editor-settings-motion-[margin-right] max-[500px]:px-8 lg:mr-[calc(var(--spacing)*3*var(--editor-settings-progress,0))]"
                  // A click below the article continues it.
                  onMouseUp={(event) => { if (event.target === event.currentTarget) editor.current?.focus(); }}
                >
                  <div className="relative mx-auto w-full max-w-[740px]">
                    {opened.article ? (
                      <>
                        <textarea
                          ref={titleRef} aria-label="Post title" placeholder="Post title" rows={1} autoFocus={!post} value={heading}
                          onChange={(event) => { setHeading(event.target.value.replace(/\s*\n\s*/g, " ")); changedContent(); }}
                          onBlur={() => { if (!post && heading.trim()) void save("auto"); }}
                          onKeyDown={titleKey}
                          className={cn(fieldClass, "heading-font-features mb-4 pb-1 text-[4.8rem] leading-[1.18] font-bold tracking-[-0.017em] text-foreground placeholder:font-bold placeholder:text-editor-placeholder max-[769px]:text-[3.6rem] max-[501px]:text-[2.8rem]")}
                        />
                        <div className="relative">
                          <textarea
                            ref={excerptRef} aria-label="Excerpt" placeholder="Add an excerpt" rows={1} value={fields.description}
                            onChange={(event) => changedFields({ description: event.target.value.replace(/\s*\n\s*/g, " ") })}
                            onKeyDown={excerptKey}
                            className={cn(fieldClass, "text-[2rem] leading-[1.5] font-[440] tracking-[-0.018em] text-foreground/90 placeholder:font-normal placeholder:text-editor-placeholder")}
                          />
                          <hr className="mt-4 mb-12 border-border-default" />
                        </div>
                        <ArticleEditor
                          handle={editor} initialBlocks={opened.article.blocks} summaryTitle={tldrTitles[fields.lang]} dark={darkMode}
                          onChange={changedContent} onWords={onWords} onTyping={onTyping} onLeaveUp={onLeaveUp}
                        />
                      </>
                    ) : (
                      <>
                        <Alert className="mb-8">
                          <AlertTitle>Editing as Markdown</AlertTitle>
                          <AlertDescription>This article contains {opened.reason}, which the block editor cannot hold without changing it.</AlertDescription>
                        </Alert>
                        <MarkdownEditor value={markdown} onChange={(text) => { setMarkdown(text); changedContent(); }} onSave={() => void save("manual")} label="Article in Markdown" />
                      </>
                    )}
                  </div>
                </div>
              </div>
            </div>

            {opened.article && (
              <div className="pointer-events-none absolute right-[calc(var(--spacing)*(4+2*var(--editor-settings-progress,0)))] bottom-3 z-20 editor-settings-motion-[right] max-[500px]:right-3" data-writing-focus={writingFocus}>
                <span className={pill}>{words.selected ? `${words.selected.toLocaleString("en")} of ` : ""}{words.all.toLocaleString("en")} {words.all === 1 ? "word" : "words"}</span>
              </div>
            )}
          </div>

          <div className="absolute top-[calc(var(--spacing)*5+1px)] right-[calc(var(--spacing)*6+1px)] z-40 max-[500px]:top-3 max-[500px]:right-3" data-writing-focus={writingFocus}>
            <Button
              ref={settingsToggleRef} size="icon" variant="ghost" aria-label="Settings" aria-expanded={settingsOpen}
              className={settingsOpen
                ? "bg-transparent enabled:aria-expanded:bg-transparent enabled:aria-expanded:shadow-none enabled:aria-expanded:hover:bg-sidebar-accent"
                : headerButton}
              onClick={() => { settingsToggleRef.current?.focus(); flipSettings(); }}
            >
              <PanelRight className="stroke-2!" />
            </Button>
          </div>

          {settingsPresent && (
            <PostSettingsSidebar
              frameRef={settingsFrameRef} opensInPlace={settingsMemory.restored}
              fields={fields} onChange={changedFields} post={post} heading={heading} markdownMode={!opened.article}
              onRestored={async (restored) => {
                queryClient.setQueryData(getGetPostQueryKey(restored.id), { data: restored, status: 200, headers: new Headers() });
                await refresh(restored.id);
                // Nothing of the old text is left to save: the restored post is opened afresh, as blocks or as Markdown.
                clearTimeout(timer.current);
                changes.current.savedContent = changes.current.content;
                changes.current.savedFields = changes.current.fields;
                onReopen?.();
              }}
            />
          )}
        </div>

        {post && (
          <PublishFlow
            open={publishOpen} onClose={() => setPublishOpen(false)}
            mode={post.status === "draft" ? "publish" : post.status === "scheduled" ? "unpublish-scheduled" : "unpublish-published"}
            publishedAt={post.publishedAt ? new Date(post.publishedAt) : undefined}
            onPreview={() => { setPublishOpen(false); setShowPreview(true); }}
            onPublish={(at) => act(at ? { scheduleAt: at } : "publish")}
            onUnpublish={() => act("unpublish")}
          />
        )}

        <PostPreview
          open={showPreview && Boolean(post)} onOpenChange={setShowPreview} preview={preview} problems={shownProblems} lang={fields.lang} lead={fields.description}
          approval={post?.status === "draft" ? { current: Boolean(post.approval?.current), lapsed: post.approval?.current === false, busy, onApprove: () => void approve() } : undefined}
          publish={post?.status === "draft" && <Button className="w-20 shrink-0" disabled={busy} onClick={() => { setShowPreview(false); setPublishOpen(true); }}>Publish</Button>}
        />

        <AlertDialog open={blocker.status === "blocked"} onOpenChange={(open) => { if (!open) blocker.reset?.(); }}>
          <AlertDialogContent>
            <AlertDialogHeader>
              <AlertDialogTitle>Are you sure you want to leave this page?</AlertDialogTitle>
              <AlertDialogDescription>Hey there! It looks like you didn't save the changes you made.</AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
              <AlertDialogCancel>Stay</AlertDialogCancel>
              <AlertDialogAction onClick={() => { changes.current.savedContent = changes.current.content; changes.current.savedFields = changes.current.fields; blocker.proceed?.(); }}>Leave</AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
      </div>
    </EditorHostContext.Provider>
  );
}
