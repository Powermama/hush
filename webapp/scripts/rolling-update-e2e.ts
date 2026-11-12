// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// End-to-end check that a deployment does not drop requests. Builds the
// production image and reproduces Coolify's two replacement models locally:
//
//   control  Docker Compose reconciliation: stop the old container, then start
//            the new one. Expected to fail requests; proves the probe detects
//            an outage.
//   rolling  Coolify's rolling update for Dockerfile applications: start the
//            replacement, wait for its health check, then stop the old
//            container with a grace period. Must fail zero requests.
//
// Traefik (Coolify's proxy) routes by Docker labels with a retry middleware,
// PostgreSQL runs as its own container, and every instance shares one data
// volume, as on the server.
//
// Run from webapp/: bun scripts/rolling-update-e2e.ts [--skip-build]
// Requires Docker. Uses only containers, a network and a volume prefixed hush-e2e.

const prefix = "hush-e2e";
const image = `${prefix}-web`;
const network = `${prefix}-net`;
const dataVolume = `${prefix}-data`;
const proxyPort = 18_080;
const base = `http://127.0.0.1:${proxyPort}`;
const healthInterval = "2s";

async function docker(args: string[], options: { allowFailure?: boolean } = {}) {
  const process = Bun.spawn(["docker", ...args], { stdout: "pipe", stderr: "pipe" });
  const [stdout, stderr, code] = await Promise.all([
    new Response(process.stdout).text(),
    new Response(process.stderr).text(),
    process.exited,
  ]);
  if (code !== 0 && !options.allowFailure) {
    throw new Error(`docker ${args.join(" ")} failed (${code}): ${stderr.trim()}`);
  }
  return stdout.trim();
}

async function cleanup() {
  const containers = await docker(["ps", "-aq", "--filter", `name=^${prefix}-`], { allowFailure: true });
  if (containers) await docker(["rm", "-f", ...containers.split("\n")], { allowFailure: true });
  await docker(["volume", "rm", "-f", dataVolume], { allowFailure: true });
  await docker(["network", "rm", network], { allowFailure: true });
}

async function waitFor(check: () => Promise<boolean>, what: string, timeoutMs = 90_000) {
  const end = Date.now() + timeoutMs;
  while (Date.now() < end) {
    if (await check().catch(() => false)) return;
    await Bun.sleep(250);
  }
  throw new Error(`timed out waiting for ${what}`);
}

async function startApp(name: string, extraEnv: Record<string, string> = {}) {
  const env = {
    NODE_ENV: "production",
    PORT: "3000",
    HUSH_PUBLIC_BASE_URL: "https://behu.test",
    HUSH_DATA_DIR: "/app/data",
    HUSH_SERVICE_KEY_ID: "hush-e2e-1",
    DATABASE_URL: `postgresql://hush:hush@${prefix}-postgres:5432/hush`,
    ...extraEnv,
  };
  await docker([
    "run", "-d", "--name", name, "--network", network,
    "-v", `${dataVolume}:/app/data`,
    // Mirrors the Coolify dashboard health check that replaces the image's slower one.
    "--health-cmd", "bun scripts/healthcheck.ts",
    "--health-interval", healthInterval, "--health-timeout", "2s",
    "--health-start-period", "5s", "--health-retries", "3",
    ...Object.entries(env).flatMap(([key, value]) => ["-e", `${key}=${value}`]),
    "-l", "traefik.enable=true",
    "-l", "traefik.http.routers.hush.rule=PathPrefix(`/`)",
    "-l", "traefik.http.routers.hush.entrypoints=web",
    "-l", "traefik.http.routers.hush.middlewares=hush-retry",
    "-l", "traefik.http.middlewares.hush-retry.retry.attempts=3",
    "-l", "traefik.http.services.hush.loadbalancer.server.port=3000",
    image,
  ]);
}

async function waitHealthy(name: string) {
  await waitFor(
    async () => (await docker(["inspect", "-f", "{{.State.Health.Status}}", name])) === "healthy",
    `${name} to become healthy`,
  );
}

// Requests visitors make, at full speed: pages, static assets and liveness.
const pageProbes: Array<{ path: string; ok: (status: number) => boolean }> = [
  { path: "/", ok: (status) => status === 200 },
  { path: "/verified-messages", ok: (status) => status === 200 },
  { path: "/favicon.svg", ok: (status) => status === 200 },
  { path: "/health/live", ok: (status) => status === 200 },
];
// The Mac app's API read, paced under the API rate limit (120 per minute per
// client) so a 429 from the limiter is never mistaken for an outage.
const apiProbe = { path: "/v1/proofs/00000000-0000-4000-8000-000000000000", ok: (status: number) => status === 404 };
const apiIntervalMs = 1_000;

function startLoad(workers = 8) {
  const result = { total: 0, failures: [] as string[] };
  let running = true;
  const request = async (probe: { path: string; ok: (status: number) => boolean }) => {
    result.total++;
    try {
      const response = await fetch(base + probe.path, { signal: AbortSignal.timeout(5_000) });
      await response.arrayBuffer();
      if (!probe.ok(response.status)) result.failures.push(`${probe.path} -> ${response.status}`);
    } catch (error) {
      result.failures.push(`${probe.path} -> ${String(error).slice(0, 60)}`);
    }
  };
  const loops = Array.from({ length: workers }, async (_, worker) => {
    let index = worker;
    while (running) await request(pageProbes[index++ % pageProbes.length]);
  });
  loops.push((async () => {
    while (running) {
      await request(apiProbe);
      await Bun.sleep(apiIntervalMs);
    }
  })());
  return async () => {
    running = false;
    await Promise.all(loops);
    return result;
  };
}

function summarize(failures: string[]) {
  const counts = new Map<string, number>();
  for (const failure of failures) counts.set(failure, (counts.get(failure) ?? 0) + 1);
  return [...counts].sort((a, b) => b[1] - a[1]).map(([failure, count]) => `${count} x ${failure}`);
}

async function keyDigest(container: string) {
  return docker(["exec", container, "sha256sum", "/app/data/service-key.json"]);
}

async function scenario(kind: "control" | "rolling") {
  await cleanup();
  await docker(["network", "create", network]);
  await docker(["volume", "create", dataVolume]);
  await docker([
    "run", "-d", "--name", `${prefix}-postgres`, "--network", network,
    "-e", "POSTGRES_DB=hush", "-e", "POSTGRES_USER=hush", "-e", "POSTGRES_PASSWORD=hush",
    "--health-cmd", "pg_isready -U hush -d hush", "--health-interval", "1s",
    "postgres:17-alpine",
  ]);
  await waitHealthy(`${prefix}-postgres`);
  await docker([
    "run", "-d", "--name", `${prefix}-proxy`, "--network", network,
    "-p", `127.0.0.1:${proxyPort}:80`,
    "-v", "/var/run/docker.sock:/var/run/docker.sock:ro",
    "traefik:v3.6",
    "--providers.docker=true", "--providers.docker.exposedbydefault=false",
    `--providers.docker.network=${network}`, "--entrypoints.web.address=:80",
  ]);

  // The first instance creates the deployment's signing key exactly once.
  await startApp(`${prefix}-a`, { HUSH_ALLOW_SERVICE_KEY_BOOTSTRAP: "1" });
  await waitHealthy(`${prefix}-a`);
  await waitFor(async () => (await fetch(`${base}/health/ready`)).ok, "proxy route");
  const keyBefore = await keyDigest(`${prefix}-a`);

  const stopLoad = startLoad();
  await Bun.sleep(2_000);
  let last = `${prefix}-a`;
  for (const next of [`${prefix}-b`, `${prefix}-c`]) {
    if (kind === "control") {
      await docker(["stop", "--time", "30", last]);
      await docker(["rm", last]);
      await startApp(next);
      await waitHealthy(next);
    } else {
      await startApp(next);
      await waitHealthy(next);
      await docker(["stop", "--time", "30", last]);
      await docker(["rm", last]);
    }
    last = next;
    await Bun.sleep(2_000);
  }
  const result = await stopLoad();
  const keyAfter = await keyDigest(last);
  return { ...result, keyStable: keyBefore.split(" ")[0] === keyAfter.split(" ")[0] };
}

const skipBuild = Bun.argv.includes("--skip-build");
try {
  if (!skipBuild) {
    console.log("Building the production image ...");
    await docker(["build", "-t", image, "."]);
  }
  const control = await scenario("control");
  console.log(`control (stop, then start): ${control.total} requests, ${control.failures.length} failed`);
  for (const line of summarize(control.failures).slice(0, 5)) console.log(`  ${line}`);
  const rolling = await scenario("rolling");
  console.log(`rolling (start, health, then stop): ${rolling.total} requests, ${rolling.failures.length} failed`);
  for (const line of summarize(rolling.failures).slice(0, 10)) console.log(`  ${line}`);

  const problems: string[] = [];
  if (control.failures.length === 0) problems.push("the control scenario dropped no requests, so the probe cannot detect an outage");
  if (rolling.failures.length > 0) problems.push(`the rolling update dropped ${rolling.failures.length} requests`);
  if (rolling.total < 500) problems.push(`only ${rolling.total} requests were sent; the probe was too slow to be meaningful`);
  if (!rolling.keyStable || !control.keyStable) problems.push("the service signing key changed across instances");
  if (problems.length) {
    console.error(`FAIL: ${problems.join("; ")}`);
    process.exitCode = 1;
  } else {
    console.log("PASS: rolling updates served every request and kept the signing key.");
  }
} finally {
  await cleanup();
}
