// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { createFileRoute } from "@tanstack/react-router";
import { PostEditor } from "@/components/post-editor";

export const Route = createFileRoute("/_editor/posts/new")({ component: () => <PostEditor /> });
