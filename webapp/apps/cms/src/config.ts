// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The CMS reads only its own settings. It never sees the proof service's
// database URL or signing key; tests/boundary.test.ts enforces that.
import type { ObjectStoreConfig } from "./storage/object-store";

type Env = Record<string, string | undefined>;

export type CmsConfig = {
  environment: "development" | "test" | "production";
  port: number;
  databaseUrl: string;
  /** Article images: Cloudflare R2 (or any S3-compatible bucket), else a local directory. */
  media: ObjectStoreConfig;
  /** Database backups, in their own private bucket, and how long to keep them. */
  backups: ObjectStoreConfig & { keepDays: number };
  /** The website the CMS deploys and reports to search engines; absent, nothing is deployed. */
  site?: SiteConfig;
};

export type SiteConfig = {
  url: string;
  coolify: { url: string; token: string; websiteUuid: string };
  /** https://www.indexnow.org key; the site serves it at /<key>.txt. */
  indexNowKey?: string;
};

export function loadConfig(env: Env = process.env): CmsConfig {
  const databaseUrl = env.CMS_DATABASE_URL;
  if (!databaseUrl) throw new Error("CMS_DATABASE_URL is required");
  const environment = env.NODE_ENV ?? "development";
  if (environment !== "development" && environment !== "test" && environment !== "production") {
    throw new Error(`NODE_ENV must be development, test or production, not ${environment}`);
  }
  const production = environment === "production";
  return {
    environment,
    port: Number(env.PORT ?? 3100),
    databaseUrl,
    media: storeConfig(env, "CMS_S3", "CMS_MEDIA_DIR", ".data/media", production),
    backups: {
      ...storeConfig(env, "CMS_BACKUP_S3", "CMS_BACKUP_DIR", ".data/backups", production),
      keepDays: Number(env.CMS_BACKUP_KEEP_DAYS ?? 30),
    },
    site: siteConfig(env),
  };
}

function siteConfig(env: Env): SiteConfig | undefined {
  const url = env.CMS_SITE_URL;
  if (!url) return undefined;
  const required = (name: string) => {
    const value = env[name];
    if (!value) throw new Error(`${name} is required when CMS_SITE_URL is set`);
    return value;
  };
  const indexNowKey = env.CMS_INDEXNOW_KEY || undefined;
  if (indexNowKey && !/^[a-zA-Z0-9-]{8,128}$/.test(indexNowKey)) throw new Error("CMS_INDEXNOW_KEY must be 8 to 128 letters, digits or dashes");
  return {
    url: new URL(url).origin,
    coolify: { url: new URL(required("CMS_COOLIFY_URL")).origin, token: required("CMS_COOLIFY_TOKEN"), websiteUuid: required("CMS_COOLIFY_WEBSITE_UUID") },
    indexNowKey,
  };
}

/** An S3 bucket when <prefix>_BUCKET is set, otherwise a directory. Production must say which. */
function storeConfig(env: Env, prefix: string, directoryVariable: string, fallback: string, production: boolean): ObjectStoreConfig {
  const bucket = env[`${prefix}_BUCKET`];
  if (bucket) {
    const required = (name: string) => {
      const value = env[`${prefix}_${name}`];
      if (!value) throw new Error(`${prefix}_${name} is required when ${prefix}_BUCKET is set`);
      return value;
    };
    return { kind: "s3", bucket, endpoint: required("ENDPOINT"), accessKeyId: required("ACCESS_KEY_ID"), secretAccessKey: required("SECRET_ACCESS_KEY") };
  }
  const directory = env[directoryVariable];
  if (production && !directory) {
    throw new Error(`Production needs ${prefix}_BUCKET (or an explicit ${directoryVariable} on a persistent volume)`);
  }
  return { kind: "local", directory: directory ?? fallback };
}
