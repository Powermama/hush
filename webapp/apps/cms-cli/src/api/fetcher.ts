// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Every call of the generated client: the CMS's origin and bearer token, set
// once before the first call. JSON answers are parsed, anything else (image
// bytes) is returned as bytes; the caller decides by status what it got.
let connection: { url: string; token: string } | undefined;

export function connect(url: string, token: string) {
  connection = { url: url.replace(/\/+$/, ""), token };
}

export async function cmsFetch<T>(path: string, init?: RequestInit): Promise<T> {
  if (!connection) throw new Error("connect() must run before the first call");
  const headers = new Headers(init?.headers);
  headers.set("authorization", `Bearer ${connection.token}`);
  const response = await fetch(`${connection.url}${path}`, { ...init, headers, redirect: "error" });
  const json = (response.headers.get("content-type") ?? "").includes("application/json");
  const data = response.status === 204 ? undefined
    : json ? await response.json() : new Uint8Array(await response.arrayBuffer());
  return { data, status: response.status, headers: response.headers } as T;
}
