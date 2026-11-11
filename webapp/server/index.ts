import { serveStatic } from "hono/bun";
import type { Context } from "hono";
import { mkdir } from "node:fs/promises";
import { createApp, registerRootProofAlias } from "./app";
import { loadConfig, loadServiceKey } from "./config";
import { ProofService } from "./services/proof-service";
import { PostgresProofRepository } from "./repositories/postgres-proof-repository";
import { SQLiteProofRepository } from "./repositories/sqlite-proof-repository";
import { LocalProofObjectStore } from "./storage/local-object-store";
import { S3ProofObjectStore } from "./storage/s3-object-store";
import { findRelease, releases } from "../shared/releases";
import { legalConfig } from "../shared/legal";
import {
  HTML_CACHE_CONTROL,
  cacheControlForStaticPath,
} from "./http/cache-policy";

const config = loadConfig();
if (config.environment !== "test") {
  await mkdir(config.dataDirectory, { recursive: true });
}
const repository = config.environment === "test" && !config.databaseUrl
  ? new SQLiteProofRepository()
  : config.databaseUrl
  ? new PostgresProofRepository(config.databaseUrl)
  : new SQLiteProofRepository(`${config.dataDirectory}/hush.sqlite`);
const objects = config.s3
  ? new S3ProofObjectStore(config.s3.bucket, config.s3)
  : new LocalProofObjectStore(`${config.dataDirectory}/objects`, config.publicBaseUrl);
const serviceKey = await loadServiceKey(config);
const proofService = new ProofService(
  repository,
  objects,
  serviceKey,
  config.publicBaseUrl,
  { shortBaseUrl: config.shortBaseUrl },
);
const app = createApp({
  proofService,
  allowedOrigin: config.allowedOrigin,
  registerRootAlias: false,
});

app.use(
  "*",
  serveStatic({
    root: "./dist",
    onFound: (path, context) => {
      context.header("cache-control", cacheControlForStaticPath(path));
    },
  }),
);
app.get("/p/*", async (context) => {
  const html = Bun.file("./dist/index.html");
  if (!(await html.exists())) {
    return context.text("Web build unavailable", 503);
  }
  context.header("cache-control", "no-store");
  context.header("x-robots-tag", "noindex, nofollow");
  return context.html(await html.text());
});
const serveReleasePage = async (context: Context) => {
  const html = Bun.file("./dist/index.html");
  if (!(await html.exists())) {
    return context.text("Web build unavailable", 503);
  }

  const slug = context.req.path.split("/").filter(Boolean).at(-1);
  const isReleaseDetail = Boolean(slug && slug !== "releases" && slug !== "latest");
  const release =
    slug && slug !== "releases" && slug !== "latest"
      ? findRelease(slug)
      : slug === "latest"
        ? releases[0]
        : undefined;
  const hasPublicRelease = releases.some(
    (candidate) => candidate.visibility === "public",
  );
  const indexable = release
    ? release.visibility === "public"
    : !isReleaseDetail && hasPublicRelease;

  context.header("cache-control", indexable ? HTML_CACHE_CONTROL : "no-store");
  if (!indexable) context.header("x-robots-tag", "noindex, nofollow");
  return context.html(await html.text(), isReleaseDetail && !release ? 404 : 200);
};
app.get("/releases", serveReleasePage);
app.get("/releases/*", serveReleasePage);
const serveLegalPage = async (context: Context) => {
  const html = Bun.file("./dist/index.html");
  if (!(await html.exists())) {
    return context.text("Web build unavailable", 503);
  }
  context.header(
    "cache-control",
    legalConfig.isPlaceholder ? "no-store" : HTML_CACHE_CONTROL,
  );
  if (legalConfig.isPlaceholder) {
    context.header("x-robots-tag", "noindex, nofollow");
  }
  return context.html(await html.text());
};
app.get("/impressum", serveLegalPage);
app.get("/datenschutz", serveLegalPage);
app.get("/de/impressum", serveLegalPage);
app.get("/de/datenschutz", serveLegalPage);
app.get("/verified-messages", async (context) => {
  const html = Bun.file("./dist/index.html");
  if (!(await html.exists())) {
    return context.text("Web build unavailable", 503);
  }
  context.header("cache-control", HTML_CACHE_CONTROL);
  return context.html(await html.text());
});
app.get("/", serveStatic({ root: "./dist", path: "index.html" }));
registerRootProofAlias(app, proofService);

const server = Bun.serve({
  port: config.port,
  fetch: app.fetch,
  idleTimeout: 30,
});

console.info(
  JSON.stringify({
    level: "info",
    message: "Hush proof service listening",
    port: server.port,
    environment: config.environment,
    storage: config.s3 ? "s3" : "local",
    database: config.databaseUrl ? "postgres" : "sqlite",
    shortBaseUrl: config.shortBaseUrl,
  }),
);
