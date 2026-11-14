// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Writing a post, as in Ghost's editor: a quiet Markdown column, the live
// preview beside it, settings in a sheet and the publish action in the top
// bar. The CMS checks the article contract on every preview, so problems show
// while writing, not only when publishing.
import { useQueryClient } from "@tanstack/react-query";
import { Link, useNavigate } from "@tanstack/react-router";
import { ArrowLeftIcon, EyeIcon, EyeOffIcon, SettingsIcon } from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { toast } from "sonner";
import {
  getGetPostQueryKey, getListPostsQueryKey, getListRevisionsQueryKey, useCreateDraft, usePreviewPost, usePublishPost,
  useSchedulePost, useUnpublishPost, useUpdatePost, type Post, type Preview,
} from "@/api/cms.generated";
import { CmsError } from "@/api/fetcher";
import { ArticlePreview } from "@/components/article-preview";
import { MarkdownEditor } from "@/components/markdown-editor";
import { PostMedia } from "@/components/post-media";
import { PostRevisions } from "@/components/post-revisions";
import { PostSettings, type PostDraft } from "@/components/post-settings";
import { PostStatusBadge, postStatusLine } from "@/components/post-status";
import { PublishMenu } from "@/components/publish-menu";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Separator } from "@/components/ui/separator";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle, SheetTrigger } from "@/components/ui/sheet";

const emptyDraft: PostDraft = {
  lang: "en", slug: "", title: "", description: "", keyword: "", secondaryKeywords: [],
  type: "how-to", cluster: "local-dictation", author: "clemens-kressmann", imageAlt: "",
  markdown: "# \n",
};

const draftOf = (post: Post): PostDraft => ({
  lang: post.lang, slug: post.slug, title: post.title, description: post.description, keyword: post.keyword,
  secondaryKeywords: post.secondaryKeywords, type: post.type, cluster: post.cluster, author: post.author,
  imageAlt: post.imageAlt, markdown: post.markdown,
});

/** The CMS's message and the contract's problems, for a toast and the problems list. */
function describe(error: unknown) {
  return error instanceof CmsError ? { message: error.message, problems: error.problems } : { message: "Something went wrong.", problems: [] };
}

export function PostEditor({ post }: { post?: Post }) {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [draft, setDraft] = useState<PostDraft>(() => (post ? draftOf(post) : emptyDraft));
  const [saved, setSaved] = useState(() => JSON.stringify(post ? draftOf(post) : emptyDraft));
  const [showPreview, setShowPreview] = useState(true);
  const [preview, setPreview] = useState<Preview | null>(null);
  const [saveProblems, setSaveProblems] = useState<string[]>([]);
  // CodeMirror owns the text while typing; a restored revision starts a new document.
  const [documentVersion, setDocumentVersion] = useState(0);
  const dirty = JSON.stringify(draft) !== saved;
  const live = post?.status === "published" || post?.status === "scheduled";

  const refresh = useCallback(async (id: string) => {
    await Promise.all([
      queryClient.invalidateQueries({ queryKey: getListPostsQueryKey() }),
      queryClient.invalidateQueries({ queryKey: getGetPostQueryKey(id) }),
      queryClient.invalidateQueries({ queryKey: getListRevisionsQueryKey(id) }),
    ]);
  }, [queryClient]);

  const create = useCreateDraft();
  const update = useUpdatePost();
  const publish = usePublishPost();
  const schedule = useSchedulePost();
  const unpublish = useUnpublishPost();
  const previewMutation = usePreviewPost();
  const busy = create.isPending || update.isPending || publish.isPending || schedule.isPending || unpublish.isPending;

  const change = (patch: Partial<PostDraft>) => setDraft((current) => ({ ...current, ...patch }));

  /** Saves the draft; returns the post id, or undefined when the CMS refused it. */
  const save = useCallback(async (): Promise<string | undefined> => {
    try {
      if (!post) {
        const created = await create.mutateAsync({ data: draft });
        const id = (created.data as Post).id;
        await refresh(id);
        toast.success("Draft created");
        await navigate({ to: "/posts/$id", params: { id }, replace: true });
        return id;
      }
      if (dirty) {
        await update.mutateAsync({ id: post.id, data: draft });
        setSaved(JSON.stringify(draft));
        await refresh(post.id);
        toast.success(live ? "Updated" : "Saved");
      }
      setSaveProblems([]);
      return post.id;
    } catch (error) {
      const { message, problems } = describe(error);
      setSaveProblems(problems);
      toast.error(message);
      return undefined;
    }
  }, [post, draft, dirty, live, create, update, refresh, navigate]);

  const run = async (action: "publish" | "unpublish" | { scheduleAt: Date }) => {
    const id = await save();
    if (!id) return;
    try {
      if (action === "publish") { await publish.mutateAsync({ id }); toast.success("Published. behu.sh updates within minutes."); }
      else if (action === "unpublish") { await unpublish.mutateAsync({ id }); toast.success("Unpublished. The page goes offline with the next deploy."); }
      else { await schedule.mutateAsync({ id, data: { publishedAt: action.scheduleAt.toISOString() } }); toast.success("Scheduled"); }
      setSaveProblems([]);
      await refresh(id);
    } catch (error) {
      const { message, problems } = describe(error);
      setSaveProblems(problems);
      toast.error(message);
    }
  };

  // The live preview: re-rendered by the CMS a moment after typing stops.
  const latest = useRef(0);
  useEffect(() => {
    if (!post || !showPreview) return;
    const request = ++latest.current;
    const timer = setTimeout(async () => {
      try {
        const result = await previewMutation.mutateAsync({ id: post.id, data: draft });
        if (request === latest.current) setPreview(result.data as Preview);
      } catch (error) {
        if (request === latest.current) setPreview({ problems: describe(error).problems.length ? describe(error).problems : [describe(error).message], rendition: null });
      }
    }, 600);
    return () => clearTimeout(timer);
    // previewMutation is stable enough for this purpose; re-running on it would loop.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [post?.id, draft, showPreview]);

  const problems = useMemo(() => [...new Set([...saveProblems, ...(preview?.problems ?? [])])], [saveProblems, preview]);
  const status = post ? postStatusLine(post) : "New draft";

  return (
    <div className="flex min-h-dvh flex-col">
      {/* On a phone the status takes a second line instead of disappearing. */}
      <header className="sticky top-0 z-10 flex flex-wrap items-center gap-x-3 gap-y-1 border-b border-border bg-background/95 px-3 py-2 backdrop-blur sm:h-14 sm:flex-nowrap sm:py-0 md:px-5">
        <Button asChild variant="ghost" size="sm"><Link to="/"><ArrowLeftIcon />Posts</Link></Button>
        <div className="order-last flex min-w-0 basis-full items-center gap-2 px-2 pb-1 text-[13px] text-muted-foreground sm:order-none sm:basis-auto sm:p-0">
          {post && <PostStatusBadge status={post.status} />}
          <span className="truncate">{status}</span>
          <span aria-live="polite" className="before:mr-2 before:content-['·'] empty:hidden">{busy ? "Saving…" : dirty ? "Unsaved changes" : post ? "Saved" : ""}</span>
        </div>
        <div className="ml-auto flex items-center gap-1.5">
          {post && (
            <Button variant="ghost" size="sm" onClick={() => setShowPreview((value) => !value)} aria-pressed={showPreview}>
              {showPreview ? <EyeOffIcon /> : <EyeIcon />}<span className="hidden sm:inline">{showPreview ? "Hide preview" : "Preview"}</span>
            </Button>
          )}
          <Sheet>
            <SheetTrigger asChild><Button variant="ghost" size="sm" aria-label="Post settings"><SettingsIcon /><span className="hidden sm:inline">Settings</span></Button></SheetTrigger>
            <SheetContent className="w-full overflow-y-auto sm:max-w-md">
              <SheetHeader className="px-6 pt-6"><SheetTitle>Post settings</SheetTitle><SheetDescription>Search metadata and where the post lives.</SheetDescription></SheetHeader>
              <div className="grid gap-8 px-6 pb-10">
                <PostSettings draft={draft} onChange={change} published={post?.status === "published"} />
                {post && <><Separator /><PostMedia postId={post.id} slug={draft.slug} /></>}
                {post && <><Separator /><PostRevisions postId={post.id} onRestored={async (restored) => {
                  setDraft(draftOf(restored));
                  setSaved(JSON.stringify(draftOf(restored)));
                  setDocumentVersion((version) => version + 1);
                  await refresh(post.id);
                }} /></>}
              </div>
            </SheetContent>
          </Sheet>
          <Button variant="outline" size="sm" onClick={() => void save()} disabled={busy || (!!post && !dirty)}>{live ? "Update" : "Save"}</Button>
          {post && <PublishMenu status={post.status} busy={busy} onPublish={() => void run("publish")} onSchedule={(at) => void run({ scheduleAt: at })} onUnpublish={() => void run("unpublish")} />}
        </div>
      </header>

      <div className={showPreview && post ? "grid flex-1 lg:grid-cols-2" : "flex-1"}>
        <section className="mx-auto w-full max-w-[740px] px-5 py-8 md:px-10" aria-label="Article">
          <MarkdownEditor key={documentVersion} value={draft.markdown} onChange={(markdown) => change({ markdown })} onSave={() => void save()} label="Article in Markdown" />
        </section>
        {showPreview && post && (
          <aside className="border-t border-border bg-muted/40 p-4 lg:sticky lg:top-14 lg:h-[calc(100dvh-3.5rem)] lg:overflow-y-auto lg:border-t-0 lg:border-l" aria-label="Preview">
            {problems.length > 0 && (
              <Alert variant="destructive" className="mb-4">
                <AlertTitle>Not ready to publish</AlertTitle>
                <AlertDescription><ul className="mt-1 list-disc pl-4">{problems.map((problem) => <li key={problem}>{problem}</li>)}</ul></AlertDescription>
              </Alert>
            )}
            {preview?.rendition
              ? <ArticlePreview heading={preview.rendition.heading} html={preview.rendition.html} />
              : <p className="p-6 text-sm text-muted-foreground">{preview ? "The preview appears once the article meets the contract." : "Rendering the preview…"}</p>}
          </aside>
        )}
      </div>
      {!post && <p className="px-5 pb-6 text-center text-xs text-muted-foreground md:px-10">Fill in the settings and save the draft to see the preview.</p>}
    </div>
  );
}
