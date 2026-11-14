// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The editor takes the whole window, as Ghost's does; sign-in still comes first.
import { Outlet, createFileRoute } from "@tanstack/react-router";
import { requireSession } from "@/api/require-session";

export const Route = createFileRoute("/_editor")({ beforeLoad: requireSession, component: Outlet });
