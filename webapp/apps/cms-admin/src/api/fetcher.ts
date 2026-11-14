// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Every API call of the admin: same origin, the session cookie, JSON errors
// turned into CmsError so screens can show the CMS's message and problems.
export class CmsError extends Error {
  constructor(readonly status: number, readonly code: string, message: string, readonly problems: string[] = []) {
    super(message);
  }
}

export async function cmsFetch<T>(url: string, init?: RequestInit): Promise<T> {
  const response = await fetch(url, { ...init, credentials: "same-origin" });
  const body = response.status === 204 ? undefined : await response.json().catch(() => undefined);
  if (!response.ok) {
    const error = (body as { error?: { code?: string; message?: string; problems?: string[] } } | undefined)?.error;
    throw new CmsError(response.status, error?.code ?? "http_error", error?.message ?? `The CMS answered ${response.status}.`, error?.problems);
  }
  return { data: body, status: response.status, headers: response.headers } as T;
}
