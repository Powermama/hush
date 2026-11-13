// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The CMS reads only its own settings. It never sees the proof service's
// database URL or signing key; tests/boundary.test.ts enforces that.

export type CmsConfig = {
  environment: "development" | "test" | "production";
  port: number;
  databaseUrl: string;
  /** Cloudflare R2 (or any S3-compatible bucket) when set, otherwise a local directory. */
  media: { kind: "s3"; bucket: string; endpoint: string; accessKeyId: string; secretAccessKey: string } | { kind: "local"; directory: string };
};

export function loadConfig(env: Record<string, string | undefined> = process.env): CmsConfig {
  const databaseUrl = env.CMS_DATABASE_URL;
  if (!databaseUrl) throw new Error("CMS_DATABASE_URL is required");
  const environment = env.NODE_ENV ?? "development";
  if (environment !== "development" && environment !== "test" && environment !== "production") {
    throw new Error(`NODE_ENV must be development, test or production, not ${environment}`);
  }
  const media: CmsConfig["media"] = env.CMS_S3_BUCKET
    ? {
      kind: "s3",
      bucket: env.CMS_S3_BUCKET,
      endpoint: required(env, "CMS_S3_ENDPOINT"),
      accessKeyId: required(env, "CMS_S3_ACCESS_KEY_ID"),
      secretAccessKey: required(env, "CMS_S3_SECRET_ACCESS_KEY"),
    }
    : { kind: "local", directory: env.CMS_MEDIA_DIR ?? ".data/media" };
  if (environment === "production" && media.kind === "local" && !env.CMS_MEDIA_DIR) {
    throw new Error("Production needs CMS_S3_BUCKET (or an explicit CMS_MEDIA_DIR on a persistent volume)");
  }
  return { environment, port: Number(env.PORT ?? 3100), databaseUrl, media };
}

function required(env: Record<string, string | undefined>, name: string) {
  const value = env[name];
  if (!value) throw new Error(`${name} is required when CMS_S3_BUCKET is set`);
  return value;
}
