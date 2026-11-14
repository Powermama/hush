// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { createFileRoute } from "@tanstack/react-router";
import { getGetPostQueryOptions, useGetPost, type Post } from "@/api/cms.generated";
import { PostEditor } from "@/components/post-editor";

export const Route = createFileRoute("/_editor/posts/$id")({
  loader: ({ context, params }) => context.queryClient.ensureQueryData(getGetPostQueryOptions(params.id)),
  component: EditPost,
});

function EditPost() {
  const { id } = Route.useParams();
  const post = useGetPost(id);
  const data = post.data?.data as Post | undefined;
  // The editor keeps its own text; it is created once per post.
  return data ? <PostEditor key={data.id} post={data} /> : null;
}
