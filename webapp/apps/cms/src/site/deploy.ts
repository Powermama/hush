// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Keeps the website in step with the CMS. Each minute the scheduler compares
// the site revision the CMS holds with the one the live site serves:
// - behind: it asks Coolify to deploy the website (whose build pulls the
//   export), at most once per deploy window, so changes made meanwhile ride
//   along with the next deploy;
// - ahead of what search engines were told: it submits the changed pages to
//   IndexNow, so publishing, editing and unpublishing reach Bing and others in
//   minutes. Google does not take IndexNow; it reads the sitemap.
// Comparing revisions instead of watching deploys means it also notices
// changes that went live with an ordinary code deploy.
import { and, eq, gt, lte } from "drizzle-orm";
import type { SiteConfig } from "../config";
import type { Database } from "../db/client";
import { siteChanges, siteState } from "../db/schema";

/** A deploy normally takes two to three minutes; after this long it is asked for again. */
export const deployWindowMs = 20 * 60_000;
/** No request may hold up the scheduler's other work (due posts, backups). */
const requestTimeoutMs = 10_000;

type Fetch = (input: string, init?: RequestInit) => Promise<Response>;
export type SyncResult = { live: number; notified: string[]; deployRequested: boolean };

/** The revision the live site was built from; a site built without the CMS serves none (0). */
export async function liveRevision(site: SiteConfig, fetcher: Fetch = fetch) {
  const response = await fetcher(new URL("/blog/revision.txt", site.url).toString(), {
    headers: { "cache-control": "no-cache" }, signal: AbortSignal.timeout(requestTimeoutMs),
  });
  if (response.status === 404) return 0;
  if (!response.ok) throw new Error(`The site answered ${response.status} for its revision`);
  const revision = Number((await response.text()).trim());
  if (!Number.isSafeInteger(revision) || revision < 0) throw new Error("The site served an invalid revision");
  return revision;
}

export async function syncSite(db: Database, site: SiteConfig, fetcher: Fetch = fetch, now = new Date()): Promise<SyncResult> {
  const live = await liveRevision(site, fetcher);
  const [state] = await db.select().from(siteState);
  const result: SyncResult = { live, notified: [], deployRequested: false };

  if (live > state!.notifiedRevision) {
    const rows = await db.selectDistinct({ path: siteChanges.path }).from(siteChanges)
      .where(and(gt(siteChanges.revision, state!.notifiedRevision), lte(siteChanges.revision, live)))
      .orderBy(siteChanges.path);
    const urls = rows.map((row) => new URL(row.path, site.url).toString());
    if (urls.length && site.indexNowKey) await submitToIndexNow(site, urls, fetcher, live);
    await db.update(siteState).set({ notifiedRevision: live }).where(eq(siteState.id, 1));
    result.notified = urls;
  }

  if (state!.revision > live) {
    const waiting = state!.deployRequestedAt && state!.deployRevision! > live
      && now.getTime() - state!.deployRequestedAt.getTime() < deployWindowMs;
    if (!waiting) {
      await requestDeploy(site, fetcher);
      await db.update(siteState).set({ deployRevision: state!.revision, deployRequestedAt: now }).where(eq(siteState.id, 1));
      result.deployRequested = true;
    }
  }
  return result;
}

/**
 * Coolify's deploy endpoint, with a token that may only deploy the website.
 * `force` makes Coolify build: without it, Coolify reuses the image of the
 * current commit, which still holds the previous export ("Build step skipped").
 * Coolify's forced builds run without the Docker cache, so they take minutes.
 */
async function requestDeploy(site: SiteConfig, fetcher: Fetch) {
  const response = await fetcher(new URL("/api/v1/deploy", site.coolify.url).toString(), {
    method: "POST",
    headers: { authorization: `Bearer ${site.coolify.token}`, "content-type": "application/json", accept: "application/json" },
    body: JSON.stringify({ uuid: site.coolify.websiteUuid, force: true }),
    signal: AbortSignal.timeout(requestTimeoutMs),
  });
  if (!response.ok) throw new Error(`Coolify refused the deploy (${response.status})`);
}

/** https://www.indexnow.org/documentation: one request for up to 10,000 URLs of one host. */
async function submitToIndexNow(site: SiteConfig, urls: string[], fetcher: Fetch, revision: number) {
  const origin = new URL(site.url);
  const response = await fetcher("https://api.indexnow.org/indexnow", {
    method: "POST",
    headers: { "content-type": "application/json; charset=utf-8" },
    body: JSON.stringify({
      host: origin.host,
      key: site.indexNowKey,
      keyLocation: new URL(`/${site.indexNowKey}.txt`, origin).toString(),
      urlList: urls,
    }),
    signal: AbortSignal.timeout(requestTimeoutMs),
  });
  if (response.status === 200 || response.status === 202) return;
  // Rate limits and server errors pass; the next tick retries them.
  if (response.status === 429 || response.status >= 500) throw new Error(`IndexNow answered ${response.status}`);
  // Any other answer (403: key file not found, 422: URLs not on the host) would
  // fail again on every retry, so it is logged once and the revision counts as done.
  console.error(JSON.stringify({ level: "error", message: "IndexNow refused the submission", status: response.status, revision, urls }));
}
