// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann

/** A request the CMS refuses, with the HTTP status and code the API answers with. */
export class PostError extends Error {
  constructor(readonly status: 404 | 409 | 422, readonly code: string, message: string, readonly problems: string[] = []) {
    super(message);
  }
}
