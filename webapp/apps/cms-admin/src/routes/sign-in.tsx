// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { createFileRoute } from "@tanstack/react-router";
import { HushLogo } from "@/components/hush-logo";
import { Button } from "@/components/ui/button";

export const Route = createFileRoute("/sign-in")({
  // Where to return after GitHub; the CMS accepts only its own paths (routes/auth.ts).
  validateSearch: (search: Record<string, unknown>): { next?: string } => (typeof search.next === "string" ? { next: search.next } : {}),
  component: SignIn,
});

function SignIn() {
  const { next } = Route.useSearch();
  return (
    <main className="flex min-h-dvh items-center justify-center bg-gray-50 px-4">
      <div className="w-full max-w-sm rounded-xl bg-white p-8 shadow-md">
        <HushLogo />
        <h1 className="mt-8 text-2xl font-semibold tracking-tight">Sign in to the CMS</h1>
        <p className="mt-2 text-sm text-muted-foreground">Write, schedule and publish the hush blog.</p>
        <Button asChild size="lg" className="mt-8 w-full">
          {/* A full navigation: GitHub redirects back to /auth/github/callback. */}
          <a href={next ? `/auth/github?next=${encodeURIComponent(next)}` : "/auth/github"}>Sign in with GitHub</a>
        </Button>
      </div>
    </main>
  );
}
