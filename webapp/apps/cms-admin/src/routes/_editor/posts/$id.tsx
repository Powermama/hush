// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// A post in the editor. /posts/new is a post not saved yet: its first save
// moves the address to the post's id while the same editor stays open, as in
// Ghost, so the cursor and undo history survive.
import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { getGetPostQueryOptions, useGetPost, type Post } from "@/api/cms.generated";
import { PostEditor } from "@/components/post-editor";

/** Posts created in this tab by an editor opened at /posts/new; it stays open on their address. */
const createdHere = new Set<string>();

export const Route = createFileRoute("/_editor/posts/$id")({
  loader: ({ context, params }) => (params.id === "new" ? undefined : context.queryClient.ensureQueryData(getGetPostQueryOptions(params.id))),
  component: EditPost,
});

function EditPost() {
  const { id } = Route.useParams();
  const navigate = Route.useNavigate();
  const isNew = id === "new";
  const post = useGetPost(id, { query: { enabled: !isNew } });
  const data = isNew ? undefined : post.data?.data as Post | undefined;
  // Opened afresh when a revision is restored.
  const [generation, setGeneration] = useState(0);
  if (!isNew && !data) return null;
  const key = isNew || createdHere.has(id) ? "new" : id;
  return (
    <PostEditor
      key={`${key}:${generation}`}
      post={data}
      onCreated={(created) => {
        createdHere.add(created);
        void navigate({ to: "/posts/$id", params: { id: created }, replace: true });
      }}
      onReopen={() => setGeneration((value) => value + 1)}
    />
  );
}
