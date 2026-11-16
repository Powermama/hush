// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Checks at start that the API's outside credentials work, so a misconfigured
// instance never reports ready and a rolling update keeps the old one: the
// media bucket answers a listing, and GitHub accepts the OAuth client secret.
// A failed check is retried until it passes; /health/ready waits for it.
import type { AdminConfig } from "./config";
import type { ObjectStore } from "./storage/object-store";

export type ConfigCheck = { name: string; run: () => Promise<void> };

/** The media bucket answers with these credentials (any S3 error, such as a bad signature, fails). */
export const storeCheck = (name: string, store: ObjectStore): ConfigCheck => ({
  name,
  run: async () => { await store.list("config-check/"); },
});

/**
 * GitHub accepts the OAuth client: asked to exchange a code that cannot exist,
 * it answers bad_verification_code for a valid client and
 * incorrect_client_credentials for a wrong secret. Only the latter fails; an
 * unreachable GitHub does not keep the CMS from serving.
 */
export const githubClientCheck = (admin: AdminConfig, fetcher: typeof fetch = fetch): ConfigCheck => ({
  name: "GitHub OAuth client",
  run: async () => {
    let answer: { error?: string };
    try {
      const response = await fetcher("https://github.com/login/oauth/access_token", {
        method: "POST",
        headers: { accept: "application/json", "content-type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({ client_id: admin.github.clientId, client_secret: admin.github.clientSecret, code: "hush-cms-config-check" }),
        signal: AbortSignal.timeout(10_000),
      });
      answer = await response.json() as { error?: string };
    } catch {
      return;
    }
    if (answer.error === "incorrect_client_credentials") throw new Error("GitHub refuses the OAuth client id or secret");
  },
});

/**
 * Runs every check until all have passed once; returns whether they have.
 * Failures are logged by name only, never with the credentials.
 */
export function watchConfiguration(checks: ConfigCheck[], options: { retryMs?: number; log?: (message: string, details: Record<string, unknown>) => void } = {}) {
  const retryMs = options.retryMs ?? 30_000;
  const log = options.log ?? ((message, details) => console.error(JSON.stringify({ level: "error", message, ...details })));
  let pending = [...checks];
  let stopped = false;
  const attempt = async () => {
    const failed: ConfigCheck[] = [];
    for (const check of pending) {
      try {
        await check.run();
      } catch (error) {
        failed.push(check);
        log("A configuration check failed; the CMS reports not ready", { check: check.name, error: String(error).slice(0, 200) });
      }
    }
    pending = failed;
    if (pending.length && !stopped) setTimeout(attempt, retryMs);
  };
  const started = attempt();
  return {
    configured: () => pending.length === 0,
    /** Resolves after the first round of checks. */
    started,
    stop: () => { stopped = true; },
  };
}
