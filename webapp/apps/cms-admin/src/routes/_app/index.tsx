// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The posts list, as Ghost Admin's (apps/admin/src/posts/list): a sticky header
// with the title, sort and "New post", then rows with a thumbnail, the title,
// "By … - in … - date" and the status in Ghost's colors, scheduled first, then
// drafts, then published. The sidebar's views filter by status. A post the
// editor just published or scheduled is celebrated here, as Ghost's list does.
import { blogAuthors, type BlogAuthorId } from "@hush/article/authors";
import { blogClusters, type BlogClusterId } from "@hush/article/taxonomy";
import { Link, createFileRoute } from "@tanstack/react-router";
import { ArrowUpDown, ImageIcon, Pen, PenLine, Plus, SearchX } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { useGetPost, useListPosts, type ListPostsStatus, type Post } from "@/api/cms.generated";
import { PostCelebrationModal } from "@/components/post-celebration-modal";
import { readPublishCelebration, type PublishCelebration } from "@/components/publish-celebration";
import { Button } from "@/components/ui/button";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/_app/")({
  validateSearch: (search: Record<string, unknown>): { status?: ListPostsStatus } => {
    const status = search.status;
    return status === "draft" || status === "scheduled" || status === "published" ? { status } : {};
  },
  component: Posts,
});

const titles: Record<string, string> = { draft: "Drafts", scheduled: "Scheduled", published: "Published" };
const sorts = { newest: "Newest first", oldest: "Oldest first", updated: "Recently updated" } as const;
type Sort = keyof typeof sorts;
const bucket = { scheduled: 0, draft: 1, published: 2 } as const;

/** Ghost's date words (posts/list/post-time.ts): relative within 12 hours, "Yesterday", else "13 Jul 2026". */
function when(iso: string) {
  const date = new Date(iso);
  const minutes = Math.round((Date.now() - date.getTime()) / 60_000);
  if (minutes >= 0 && minutes < 60) return minutes <= 1 ? "Just now" : `${minutes} minutes ago`;
  if (minutes >= 60 && minutes < 12 * 60) { const hours = Math.round(minutes / 60); return `${hours} hour${hours === 1 ? "" : "s"} ago`; }
  const yesterday = new Date(); yesterday.setDate(yesterday.getDate() - 1);
  if (date.toDateString() === yesterday.toDateString()) return "Yesterday";
  return new Intl.DateTimeFormat("en-GB", { day: "2-digit", month: "short", year: "numeric" }).format(date);
}

const relative = new Intl.RelativeTimeFormat("en", { numeric: "auto" });
function until(iso: string) {
  const minutes = Math.round((new Date(iso).getTime() - Date.now()) / 60_000);
  if (Math.abs(minutes) < 60) return relative.format(minutes, "minute");
  if (Math.abs(minutes) < 48 * 60) return relative.format(Math.round(minutes / 60), "hour");
  return relative.format(Math.round(minutes / 1440), "day");
}

function Status({ post }: { post: Post }) {
  if (post.status === "draft") return <span className="font-medium text-pink">Draft</span>;
  if (post.status === "scheduled") {
    return (
      <span className="font-medium text-green">
        Scheduled<span className="opacity-0 transition-opacity duration-200 group-hover:opacity-100"> to be published {until(post.publishedAt!)}</span>
      </span>
    );
  }
  return <span className="text-muted-foreground">Published</span>;
}

function PostRow({ post }: { post: Post }) {
  const author = blogAuthors[post.author as BlogAuthorId]?.name ?? post.author;
  const topic = blogClusters[post.cluster as BlogClusterId]?.[post.lang as "en" | "de"] ?? post.cluster;
  const date = post.status === "published" ? post.publishedAt! : post.updatedAt;
  return (
    <li className="group border-b border-border-default hover:bg-table-row-hover">
      <div className="flex items-center gap-3 pr-4">
        <Link to="/posts/$id" params={{ id: post.id }} className="flex min-w-0 flex-1 items-start gap-4 py-4 pl-4 no-underline focus-visible:ring-1 focus-visible:ring-focus-ring focus-visible:ring-inset">
          <span aria-hidden className="flex aspect-[16/10] w-[80px] shrink-0 items-center justify-center rounded-sm bg-muted lg:w-[100px]">
            <ImageIcon size={18} className="text-muted-foreground/50" />
          </span>
          <span className="flex min-w-0 flex-1 flex-col gap-1">
            <h3 className="truncate text-md font-semibold tracking-normal text-foreground">{post.rendition?.heading ?? post.title}</h3>
            <span className="truncate text-sm text-text-secondary">
              By {author} - in {topic} - {when(date)}{post.lang === "de" ? " - Deutsch" : ""}
            </span>
            <span className="text-sm"><Status post={post} /></span>
          </span>
        </Link>
        <Button asChild size="icon" variant="ghost" className="my-4 ms-8 shrink-0 text-muted-foreground group-hover:border group-hover:border-border hover:bg-background hover:text-foreground">
          <Link to="/posts/$id" params={{ id: post.id }} aria-label={`Edit ${post.title}`}><Pen /></Link>
        </Button>
      </div>
    </li>
  );
}

/**
 * The celebration the editor handed over: read once, on mount, and cleared as it
 * is read. StrictMode runs the effect twice; the ref keeps the second run from
 * reading the cleared key and dropping the celebration.
 */
function usePublishCelebration() {
  const [celebration, setCelebration] = useState<PublishCelebration | null>(null);
  const read = useRef(false);
  useEffect(() => {
    if (read.current) return;
    read.current = true;
    setCelebration(readPublishCelebration());
  }, []);
  const post = useGetPost(celebration?.id ?? "", { query: { enabled: Boolean(celebration) } });
  // The count does not hold the celebration back: the copy says "Spread the word!" until it lands.
  const published = useListPosts({ status: "published" }, { query: { enabled: celebration?.wasPublished === true } });
  const list = published.data?.data;
  return {
    celebration,
    post: celebration ? post.data?.data as Post | undefined : undefined,
    postCount: list && "posts" in list ? list.posts.length : undefined,
    dismiss: () => setCelebration(null),
  };
}

function Posts() {
  const celebration = usePublishCelebration();
  const { status } = Route.useSearch();
  const [sort, setSort] = useState<Sort>("newest");
  const posts = useListPosts(status ? { status } : undefined);
  const data = posts.data?.data;
  const rows = [...(data && "posts" in data ? data.posts : [])].sort((a, b) => {
    if (sort === "updated") return b.updatedAt.localeCompare(a.updatedAt);
    const order = bucket[a.status] - bucket[b.status];
    if (order) return order;
    const at = (post: Post) => post.publishedAt ?? post.updatedAt;
    return sort === "oldest" ? at(a).localeCompare(at(b)) : at(b).localeCompare(at(a));
  });

  return (
    <div className="mx-auto flex h-full w-full max-w-(--content-width) flex-col px-(--page-gutter)">
      <header className="sticky top-0 z-50 -mx-(--page-gutter) flex items-start justify-between gap-5 bg-gradient-to-b from-background via-background/70 to-background/70 px-(--page-gutter) pt-[28px] pb-5 backdrop-blur-md">
        <h1 className="text-lg font-semibold tracking-[0.1px] whitespace-nowrap">{status ? titles[status] : "Posts"}</h1>
        <div className="flex min-h-(--control-height) items-center gap-2">
          <Select value={sort} onValueChange={(value) => setSort(value as Sort)}>
            <Tooltip>
              <TooltipTrigger asChild>
                <SelectTrigger
                  aria-label={`Sort: ${sorts[sort]}`} shape="pill" showChevron={false} variant="ghost"
                  className="w-auto gap-1.5 font-medium [&_svg]:size-4 [&_svg]:shrink-0 [&_svg]:stroke-2! [&>svg]:mr-0"
                >
                  <ArrowUpDown className="size-4" />
                  <SelectValue>{sorts[sort]}</SelectValue>
                </SelectTrigger>
              </TooltipTrigger>
              <TooltipContent side="bottom" variant="white">Sort</TooltipContent>
            </Tooltip>
            <SelectContent align="end">
              {(Object.keys(sorts) as Sort[]).map((key) => <SelectItem key={key} value={key}>{sorts[key]}</SelectItem>)}
            </SelectContent>
          </Select>
          <div className="ms-3 shrink-0">
            <Button asChild className="font-bold [&_svg]:stroke-2!">
              <Link to="/posts/$id" params={{ id: "new" }} aria-label="New post"><Plus className="size-4" /><span className="hidden sm:inline">New post</span></Link>
            </Button>
          </div>
        </div>
      </header>

      {posts.isPending && <div className="flex grow items-center justify-center py-24 text-sm text-muted-foreground">Loading…</div>}
      {posts.isError && <p className="py-24 text-center text-sm text-destructive">Error loading posts</p>}
      {!posts.isPending && !posts.isError && rows.length === 0 && (
        <div className="flex grow flex-col items-center justify-center gap-3 py-24">
          <span className="flex size-12 items-center justify-center rounded-full bg-muted [&_svg]:size-4">{status ? <SearchX /> : <PenLine />}</span>
          <p className="text-md font-medium">{status ? `No ${titles[status]!.toLowerCase()} posts` : "Start creating content."}</p>
          {status
            ? <Button asChild variant="outline"><Link to="/" search={{}}>Show all posts</Link></Button>
            : <Button asChild><Link to="/posts/$id" params={{ id: "new" }}>Write a new post</Link></Button>}
        </div>
      )}
      {rows.length > 0 && <ul className={cn("border-t border-border-default pb-4 lg:pb-8")}>{rows.map((post) => <PostRow key={post.id} post={post} />)}</ul>}
      {celebration.celebration && celebration.post && (
        <PostCelebrationModal
          post={celebration.post} wasPublished={celebration.celebration.wasPublished} postCount={celebration.postCount} onClose={celebration.dismiss}
        />
      )}
    </div>
  );
}
