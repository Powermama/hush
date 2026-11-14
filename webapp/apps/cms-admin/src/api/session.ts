// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The signed-in admin. Sign-in itself lives outside the OpenAPI document
// (/auth, browser redirects), so these two calls are written by hand.
import { queryOptions } from "@tanstack/react-query";
import { cmsFetch } from "./fetcher";

export type Session = { login: string };

export const sessionQuery = queryOptions({
  queryKey: ["session"],
  queryFn: async () => (await cmsFetch<{ data: Session }>("/auth/session")).data,
  retry: false,
  staleTime: 60_000,
});

export async function signOut() {
  await cmsFetch("/auth/sign-out", { method: "POST" });
}
