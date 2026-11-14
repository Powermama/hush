// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { Link, createFileRoute } from "@tanstack/react-router";
import { PlusIcon } from "lucide-react";
import { useListPosts, type ListPostsStatus } from "@/api/cms.generated";
import { PostStatusBadge, postStatusLine } from "@/components/post-status";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";

const filters = ["all", "draft", "scheduled", "published"] as const;
type Filter = (typeof filters)[number];
const filterLabels: Record<Filter, string> = { all: "All", draft: "Drafts", scheduled: "Scheduled", published: "Published" };

export const Route = createFileRoute("/_app/")({
  validateSearch: (search: Record<string, unknown>): { status?: ListPostsStatus } => {
    const status = search.status;
    return status === "draft" || status === "scheduled" || status === "published" ? { status } : {};
  },
  component: Posts,
});

function Posts() {
  const { status } = Route.useSearch();
  const navigate = Route.useNavigate();
  const posts = useListPosts(status ? { status } : undefined);
  const rows = posts.data?.data && "posts" in posts.data.data ? posts.data.data.posts : [];
  return (
    <main className="mx-auto w-full max-w-5xl px-4 py-8 md:px-10 md:py-10">
      <header className="flex items-center justify-between gap-4">
        <h1 className="text-[28px] font-semibold tracking-[-0.02em]">Posts</h1>
        <Button asChild><Link to="/posts/new"><PlusIcon />New post</Link></Button>
      </header>
      <Tabs value={status ?? "all"} onValueChange={(value) => navigate({ search: value === "all" ? {} : { status: value as ListPostsStatus } })} className="mt-6">
        <TabsList>{filters.map((filter) => <TabsTrigger key={filter} value={filter}>{filterLabels[filter]}</TabsTrigger>)}</TabsList>
      </Tabs>
      <ul className="mt-4 divide-y divide-border border-y border-border">
        {posts.isPending && [0, 1, 2].map((index) => <li key={index} className="py-4"><Skeleton className="h-5 w-2/3" /><Skeleton className="mt-2 h-4 w-1/3" /></li>)}
        {!posts.isPending && rows.length === 0 && (
          <li className="py-16 text-center text-sm text-muted-foreground">{status ? `No ${filterLabels[status].toLowerCase()} posts.` : "No posts yet."}</li>
        )}
        {rows.map((post) => (
          <li key={post.id}>
            <Link to="/posts/$id" params={{ id: post.id }} className="group flex items-center gap-4 py-4 outline-none">
              <div className="min-w-0 flex-1">
                <p className="truncate text-[15px] font-semibold group-hover:underline group-focus-visible:underline">{post.rendition?.heading ?? post.title}</p>
                <p className="mt-1 text-[13px] text-muted-foreground">
                  <span className="uppercase">{post.lang}</span> · /{post.lang === "de" ? "de/" : ""}blog/{post.slug} · {postStatusLine(post)}
                </p>
              </div>
              <PostStatusBadge status={post.status} />
            </Link>
          </li>
        ))}
      </ul>
    </main>
  );
}
