// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// End-to-end check that replacing the CMS API does not drop requests, as the
// website's scripts/rolling-update-e2e.ts does for behu.sh. Builds the image and
// reproduces both replacement models:
//
//   control  Docker Compose: stop the old container, then start the new one.
//            Expected to fail requests; proves the probe detects an outage.
//   rolling  A rolling update (Coolify applications, Kubernetes, Fly.io, ...):
//            start the replacement, wait for its health check, then stop the
//            old container with a grace period. Must fail zero requests.
//
// Traefik (Coolify's proxy) routes by Docker labels without a retry middleware,
// so the API alone must not drop requests: it reports not-ready on SIGTERM and
// finishes what it has (src/index.ts). PostgreSQL runs as its own container.
//
// Run from webapp/apps/cms/: bun scripts/rolling-update-e2e.ts [--skip-build]
// Requires Docker. Uses only containers, a network and a volume prefixed hush-cms-e2e.

const prefix = "hush-cms-e2e";
const image = `${prefix}-api`;
const network = `${prefix}-net`;
const mediaVolume = `${prefix}-media`;
const proxyPort = 18_081;
const base = `http://127.0.0.1:${proxyPort}`;

async function docker(args: string[], options: { allowFailure?: boolean } = {}) {
  const process = Bun.spawn(["docker", ...args], { stdout: "pipe", stderr: "pipe" });
  const [stdout, stderr, code] = await Promise.all([new Response(process.stdout).text(), new Response(process.stderr).text(), process.exited]);
  if (code !== 0 && !options.allowFailure) throw new Error(`docker ${args.join(" ")} failed (${code}): ${stderr.trim()}`);
  return stdout.trim();
}

async function cleanup() {
  const containers = await docker(["ps", "-aq", "--filter", `name=^${prefix}-`], { allowFailure: true });
  if (containers) await docker(["rm", "-f", ...containers.split("\n")], { allowFailure: true });
  await docker(["volume", "rm", "-f", mediaVolume], { allowFailure: true });
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

async function startApi(name: string) {
  const env = {
    // The test environment stores images on a volume instead of R2; everything else is production's.
    NODE_ENV: "test",
    PORT: "3100",
    CMS_DATABASE_URL: `postgresql://cms:cms@${prefix}-postgres:5432/cms`,
    CMS_MEDIA_DIR: "/app/data/media",
    CMS_BACKUP_DIR: "/app/data/backups",
  };
  await docker([
    "run", "-d", "--name", name, "--network", network, "-v", `${mediaVolume}:/app/data`,
    // A quicker health check than the image's own, as a platform's dashboard sets it.
    "--health-cmd", "bun -e \"fetch('http://127.0.0.1:3100/health/ready').then((r) => process.exit(r.ok ? 0 : 1), () => process.exit(1))\"",
    "--health-interval", "2s", "--health-timeout", "2s", "--health-start-period", "5s", "--health-retries", "3",
    ...Object.entries(env).flatMap(([key, value]) => ["-e", `${key}=${value}`]),
    "-l", "traefik.enable=true",
    "-l", "traefik.http.routers.cms.rule=PathPrefix(`/`)",
    "-l", "traefik.http.routers.cms.entrypoints=web",
    "-l", "traefik.http.services.cms.loadbalancer.server.port=3100",
    image,
  ]);
}

const waitHealthy = (name: string) => waitFor(
  async () => (await docker(["inspect", "-f", "{{.State.Health.Status}}", name])) === "healthy", `${name} to become healthy`,
);

// What the admin and agents request: the admin itself, the API description and public reads.
const probes = ["/", "/openapi.json", "/robots.txt", "/health/live"];

function startLoad(workers = 8) {
  const result = { total: 0, failures: [] as string[] };
  let running = true;
  const loops = Array.from({ length: workers }, async (_, worker) => {
    let index = worker;
    while (running) {
      const path = probes[index++ % probes.length]!;
      result.total++;
      try {
        const response = await fetch(base + path, { signal: AbortSignal.timeout(5_000) });
        await response.arrayBuffer();
        if (response.status !== 200) result.failures.push(`${path} -> ${response.status}`);
      } catch (error) {
        result.failures.push(`${path} -> ${String(error).slice(0, 60)}`);
      }
    }
  });
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

async function scenario(kind: "control" | "rolling") {
  await cleanup();
  await docker(["network", "create", network]);
  await docker(["volume", "create", mediaVolume]);
  await docker([
    "run", "-d", "--name", `${prefix}-postgres`, "--network", network,
    "-e", "POSTGRES_DB=cms", "-e", "POSTGRES_USER=cms", "-e", "POSTGRES_PASSWORD=cms",
    "--health-cmd", "pg_isready -U cms -d cms", "--health-interval", "1s", "postgres:17-alpine",
  ]);
  await waitHealthy(`${prefix}-postgres`);
  await docker([
    "run", "-d", "--name", `${prefix}-proxy`, "--network", network, "-p", `127.0.0.1:${proxyPort}:80`,
    "-v", "/var/run/docker.sock:/var/run/docker.sock:ro", "traefik:v3.6",
    "--providers.docker=true", "--providers.docker.exposedbydefault=false",
    `--providers.docker.network=${network}`, "--entrypoints.web.address=:80",
  ]);

  await startApi(`${prefix}-a`);
  await waitHealthy(`${prefix}-a`);
  await waitFor(async () => (await fetch(`${base}/health/ready`)).ok, "proxy route");

  const stopLoad = startLoad();
  await Bun.sleep(2_000);
  let last = `${prefix}-a`;
  for (const next of [`${prefix}-b`, `${prefix}-c`]) {
    if (kind === "control") {
      await docker(["stop", "--time", "30", last]);
      await docker(["rm", last]);
      await startApi(next);
      await waitHealthy(next);
    } else {
      // Start the replacement, wait for its health check and for the proxy to send it traffic, then stop the old one.
      await startApi(next);
      await waitHealthy(next);
      await Bun.sleep(5_000);
      await docker(["stop", "--time", "30", last]);
      await docker(["rm", last]);
    }
    last = next;
    await Bun.sleep(2_000);
  }
  return stopLoad();
}

const skipBuild = Bun.argv.includes("--skip-build");
try {
  if (!skipBuild) {
    console.log("Building the CMS image ...");
    await docker(["build", "-t", image, "--file", "Dockerfile", "../.."]);
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
  if (problems.length) {
    console.error(`FAIL: ${problems.join("; ")}`);
    process.exitCode = 1;
  } else {
    console.log("PASS: rolling updates served every request.");
  }
} finally {
  await cleanup();
}
