import { serveStatic } from "hono/bun";
import { mkdir } from "node:fs/promises";
import { createApp, registerRootProofAlias } from "./app";
import { loadConfig, loadServiceKey } from "./config";
import { startProofCleanup } from "./services/proof-cleanup";
import { ProofService } from "./services/proof-service";
import { PostgresProofRepository } from "./repositories/postgres-proof-repository";
import { SQLiteProofRepository } from "./repositories/sqlite-proof-repository";
import { LocalProofObjectStore } from "./storage/local-object-store";
import { S3ProofObjectStore } from "./storage/s3-object-store";
import { latestRelease, releasePath } from "../shared/releases";
import { sitePages } from "../shared/site";
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
let draining = false;
const app = createApp({
  proofService,
  allowedOrigin: config.allowedOrigin,
  registerRootAlias: false,
  readOnly: config.readOnly,
  // Ready only while not draining and the database answers promptly. The
  // proxy and Coolify's rolling update both rely on this being truthful.
  readiness: async () => !draining && await Promise.race([
    repository.ping().then(() => true),
    Bun.sleep(2_000).then(() => false),
  ]),
});

const pageFile = Bun.file("./dist-pages/pages.json");
const renderedPages: Record<string, string> = await pageFile.exists() ? await pageFile.json() : {};
for (const [path, metadata] of Object.entries(sitePages)) {
  app.get(path, (context) => {
    const html = renderedPages[path];
    if (!html) return context.text("Web build unavailable", 503);
    context.header("cache-control", metadata.indexable ? HTML_CACHE_CONTROL : "no-store");
    if (!metadata.indexable) context.header("x-robots-tag", "noindex, nofollow");
    return context.html(html);
  });
}
// A moving alias must not create an independently indexed duplicate.
app.get("/releases/latest", context => context.redirect(latestRelease ? releasePath(latestRelease) : "/releases", 302));
app.get("/p/*", async (context) => {
  const html = Bun.file("./dist/index.html");
  if (!(await html.exists())) {
    return context.text("Web build unavailable", 503);
  }
  context.header("cache-control", "no-store");
  context.header("x-robots-tag", "noindex, nofollow");
  return context.html(await html.text());
});
app.get("/releases/*", async (context) => {
  const html = Bun.file("./dist/index.html");
  if (!(await html.exists())) {
    return context.text("Web build unavailable", 503);
  }

  context.header("cache-control", "no-store");
  context.header("x-robots-tag", "noindex, nofollow");
  return context.html(await html.text(), 404);
});
app.get("/index.html", context => context.redirect("/", 308));
app.use("*", serveStatic({
  root: "./dist",
  onFound: (path, context) => context.header("cache-control", cacheControlForStaticPath(path)),
}));
registerRootProofAlias(app, proofService);

const cleanup = startProofCleanup(repository, objects);
const server = Bun.serve({
  port: config.port,
  // While draining, ask the proxy to close each connection after its response.
  // Otherwise it keeps reusing idle keep-alive connections to this instance,
  // and a request sent on one after the listener closes hangs until it times out.
  fetch: async (request, bunServer) => {
    const response = await app.fetch(request, bunServer);
    if (!draining) return response;
    const headers = new Headers(response.headers);
    headers.set("connection", "close");
    return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
  },
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

// Graceful shutdown for rolling updates. Coolify starts the replacement, waits
// for its health check, then stops this instance with a grace period (30 s by
// default). Keep answering during the drain so requests the proxy still routes
// here succeed, report not-ready so health checks move traffic away, then stop
// listening without dropping in-flight requests and exit inside the grace period.
let stopping = false;
async function shutdown(signal: string) {
  if (stopping) return;
  stopping = true;
  draining = true;
  console.info(JSON.stringify({
    level: "info",
    message: "Draining before shutdown",
    signal,
    drainMs: config.shutdownDrainMs,
  }));
  await Bun.sleep(config.shutdownDrainMs);
  // Let requests already in flight finish (bounded), then close every remaining
  // connection at once, so no idle keep-alive connection is left half-open.
  const deadline = Date.now() + 10_000;
  while (server.pendingRequests > 0 && Date.now() < deadline) await Bun.sleep(50);
  await server.stop(true);
  await cleanup.stop();
  await repository.close();
  console.info(JSON.stringify({ level: "info", message: "Hush proof service stopped" }));
  process.exit(0);
}
process.once("SIGTERM", () => void shutdown("SIGTERM"));
process.once("SIGINT", () => void shutdown("SIGINT"));
