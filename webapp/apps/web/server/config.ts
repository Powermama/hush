import { link, mkdir, rename, unlink, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import {
  createEphemeralServiceKey,
  importServiceKey,
  type PublicServiceJwk,
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
  /** Id of a key supplied through HUSH_SERVICE_PRIVATE_JWK; generated keys name themselves. */
  serviceKeyId?: string;
  servicePrivateJwk?: JsonWebKey;
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

/**
 * The service's receipt-signing key. Nobody needs to know or back it up: when
 * none exists, the service generates one, and every public key it ever signed
 * with stays in service-public-keys.json next to it, so receipts verify with
 * the key they name. Replacing the key (delete service-key.json and restart)
 * therefore never breaks earlier proofs. Both files live in the data volume
 * with the encrypted proofs; losing the volume loses those proofs anyway.
 */
export async function loadServiceKey(
  config: ServerConfig,
): Promise<ServiceSigningKey> {
  if (config.environment === "test" && !config.servicePrivateJwk) {
    return createEphemeralServiceKey();
  }
  const signing = config.servicePrivateJwk
    ? await importServiceKey(config.serviceKeyId ?? "hush-production-1", config.servicePrivateJwk)
    : await loadOrCreateKeyFile(config.dataDirectory);
  const publicKeys = await rememberPublicKey(config.dataDirectory, signing.id, signing.publicJwk);
  return { ...signing, publicKeys };
}

async function loadOrCreateKeyFile(dataDirectory: string) {
  const keyPath = join(dataDirectory, "service-key.json");
  if (!(await Bun.file(keyPath).exists())) {
    const generated = await createEphemeralServiceKey();
    const privateJwk = await crypto.subtle.exportKey("jwk", generated.privateKey);
    await mkdir(dataDirectory, { recursive: true, mode: 0o700 });
    // Instances starting together race through link(): exactly one key wins and
    // every instance then reads that one.
    const temporaryPath = `${keyPath}.${crypto.randomUUID()}.tmp`;
    await writeFile(temporaryPath, JSON.stringify({ id: generated.id, privateJwk }, null, 2), { flag: "wx", mode: 0o600 });
    try {
      await link(temporaryPath, keyPath);
      console.info(JSON.stringify({ level: "info", message: "Generated a new service signing key", keyId: generated.id }));
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error;
    } finally {
      await unlink(temporaryPath);
    }
  }
  const stored = (await Bun.file(keyPath).json()) as { id: string; privateJwk: JsonWebKey };
  return importServiceKey(stored.id, stored.privateJwk);
}

/** Adds the public key to service-public-keys.json (kept forever) and returns them all. */
async function rememberPublicKey(dataDirectory: string, id: string, publicJwk: PublicServiceJwk) {
  const registryPath = join(dataDirectory, "service-public-keys.json");
  const file = Bun.file(registryPath);
  const known = (await file.exists() ? await file.json() : {}) as Record<string, PublicServiceJwk>;
  if (known[id]) {
    if (JSON.stringify(known[id]) !== JSON.stringify(publicJwk)) {
      throw new Error(`Service key id ${id} is already registered for a different key`);
    }
    return known;
  }
  const updated = { ...known, [id]: publicJwk };
  await mkdir(dataDirectory, { recursive: true, mode: 0o700 });
  const temporaryPath = `${registryPath}.${crypto.randomUUID()}.tmp`;
  await writeFile(temporaryPath, JSON.stringify(updated, null, 2), { mode: 0o644 });
  await rename(temporaryPath, registryPath);
  return updated;
}
