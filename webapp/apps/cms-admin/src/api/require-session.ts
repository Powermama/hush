// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import type { QueryClient } from "@tanstack/react-query";
import { redirect } from "@tanstack/react-router";
import { CmsError } from "./fetcher";
import { sessionQuery } from "./session";

/** beforeLoad for every screen behind sign-in: without a session, go to /sign-in first, and come back after. */
export async function requireSession({ context, location }: { context: { queryClient: QueryClient }; location: { href: string } }) {
  try {
    await context.queryClient.ensureQueryData(sessionQuery);
  } catch (error) {
    if (error instanceof CmsError && error.status === 401) throw redirect({ to: "/sign-in", search: { next: location.href === "/" ? undefined : location.href } });
    throw error;
  }
}
