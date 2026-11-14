// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import type { QueryClient } from "@tanstack/react-query";
import { redirect } from "@tanstack/react-router";
import { CmsError } from "./fetcher";
import { sessionQuery } from "./session";

/** beforeLoad for every screen behind sign-in: without a session, go to /sign-in first. */
export async function requireSession({ context }: { context: { queryClient: QueryClient } }) {
  try {
    await context.queryClient.ensureQueryData(sessionQuery);
  } catch (error) {
    if (error instanceof CmsError && error.status === 401) throw redirect({ to: "/sign-in" });
    throw error;
  }
}
