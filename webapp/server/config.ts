import { link, mkdir, unlink, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import {
  createEphemeralServiceKey,
  importServiceKey,
  type ServiceSigningKey,
} from "./crypto/p256";

export type ServerConfig = {
  environment: "development" | "test" | "production";
  port: number;
  publicBaseUrl: string;
  shortBaseUrl: string;
  dataDirectory: string;
  databaseUrl?: string;
  allowedOrigin: string;
  serviceKeyId?: string;
  servicePrivateJwk?: JsonWebKey;
  /** Allows a production service to create its first signing key. Off by default. */
  allowServiceKeyBootstrap: boolean;
  /** Rejects proof writes with 503 while every read keeps working (data migrations). */
  readOnly: boolean;
  /** How long a stopping instance keeps serving before it closes its listener. */
  shutdownDrainMs: number;
  s3?: {
    bucket: string;
    region: string;
    endpoint?: string;
    accessKeyId?: string;
    secretAccessKey?: string;
  };
};

export function loadConfig(env = process.env): ServerConfig {
  const environment = (env.NODE_ENV ?? "development") as ServerConfig["environment"];
  const publicBaseUrl = env.HUSH_PUBLIC_BASE_URL ?? "http://127.0.0.1:3000";
  const shortBaseUrl = normalizeBaseUrl(
    env.HUSH_SHORT_BASE_URL ?? new URL("/s/", publicBaseUrl).toString(),
    environment,
  );
  const dataDirectory = resolve(env.HUSH_DATA_DIR ?? ".data");
  const privateJwk = env.HUSH_SERVICE_PRIVATE_JWK
    ? (JSON.parse(env.HUSH_SERVICE_PRIVATE_JWK) as JsonWebKey)
    : undefined;
  const s3 = env.HUSH_S3_BUCKET
    ? {
        bucket: env.HUSH_S3_BUCKET,
        region: env.HUSH_S3_REGION ?? "auto",
        endpoint: env.HUSH_S3_ENDPOINT,
        accessKeyId: env.HUSH_S3_ACCESS_KEY_ID,
        secretAccessKey: env.HUSH_S3_SECRET_ACCESS_KEY,
      }
    : undefined;
  return {
    environment,
    port: Number(env.PORT ?? 3000),
    publicBaseUrl,
    shortBaseUrl,
    dataDirectory,
    databaseUrl: env.DATABASE_URL,
    allowedOrigin: env.HUSH_ALLOWED_ORIGIN ?? new URL(publicBaseUrl).origin,
    serviceKeyId: env.HUSH_SERVICE_KEY_ID,
    servicePrivateJwk: privateJwk,
    allowServiceKeyBootstrap: env.HUSH_ALLOW_SERVICE_KEY_BOOTSTRAP === "1",
    readOnly: env.HUSH_READ_ONLY === "1",
    shutdownDrainMs: boundedInteger(env.HUSH_SHUTDOWN_DRAIN_MS, 10_000, 0, 60_000, "HUSH_SHUTDOWN_DRAIN_MS"),
    s3,
  };
}

function boundedInteger(
  value: string | undefined,
  fallback: number,
  min: number,
  max: number,
  name: string,
): number {
  if (value === undefined || value === "") return fallback;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < min || parsed > max) {
    throw new Error(`${name} must be an integer from ${min} to ${max}`);
  }
  return parsed;
}

function normalizeBaseUrl(
  value: string,
  environment: ServerConfig["environment"],
): string {
  const url = new URL(value);
  if (!["http:", "https:"].includes(url.protocol)) {
    throw new Error("HUSH_SHORT_BASE_URL must use HTTP or HTTPS");
  }
  if (environment === "production" && url.protocol !== "https:") {
    throw new Error("HUSH_SHORT_BASE_URL must use HTTPS in production");
  }
  if (url.username || url.password || url.search || url.hash) {
    throw new Error(
      "HUSH_SHORT_BASE_URL must not contain credentials, a query, or a fragment",
    );
  }
  if (!url.pathname.endsWith("/")) url.pathname += "/";
  return url.toString();
}

export async function loadServiceKey(
  config: ServerConfig,
): Promise<ServiceSigningKey> {
  if (config.servicePrivateJwk) {
    return importServiceKey(
      config.serviceKeyId ?? "hush-production-1",
      config.servicePrivateJwk,
    );
  }
  if (config.environment === "test") {
    return createEphemeralServiceKey();
  }
  const keyPath = join(config.dataDirectory, "service-key.json");
  const file = Bun.file(keyPath);
  if (await file.exists()) {
    const stored = (await file.json()) as { id: string; privateJwk: JsonWebKey };
    return importServiceKey(stored.id, stored.privateJwk);
  }
  // A missing key in production almost always means a lost or mis-mounted data
  // volume. Minting a new key would silently invalidate every existing proof,
  // so fail closed unless the operator explicitly bootstraps a new deployment.
  if (config.environment === "production" && !config.allowServiceKeyBootstrap) {
    throw new Error(
      `Service signing key not found at ${keyPath}. Mount the existing data volume, ` +
      "or set HUSH_ALLOW_SERVICE_KEY_BOOTSTRAP=1 once to create the first key.",
    );
  }
  const generatedKey = await createEphemeralServiceKey();
  const privateJwk = await crypto.subtle.exportKey(
    "jwk",
    generatedKey.privateKey,
  );
  const id = config.serviceKeyId ?? generatedKey.id;
  await mkdir(config.dataDirectory, { recursive: true, mode: 0o700 });

  const temporaryPath = `${keyPath}.${crypto.randomUUID()}.tmp`;
  await writeFile(
    temporaryPath,
    JSON.stringify({ id, privateJwk }, null, 2),
    { flag: "wx", mode: 0o600 },
  );
  try {
    await link(temporaryPath, keyPath);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error;
  } finally {
    await unlink(temporaryPath);
  }

  const stored = (await Bun.file(keyPath).json()) as {
    id: string;
    privateJwk: JsonWebKey;
  };
  return importServiceKey(stored.id, stored.privateJwk);
}
