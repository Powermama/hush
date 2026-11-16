<!-- SPDX-License-Identifier: AGPL-3.0-only -->
<!-- Copyright (c) 2026 Clemens Kressmann -->

# Deploy anywhere

hush runs as ordinary containers, so it can move between hosting platforms
(Coolify today; Kubernetes, Fly.io, Railway, Render or any Docker host) without
code changes. This page lists what each service needs from a platform. A move
is writing that platform's configuration from it, and copying the data.

## The portable parts

- **One image per service**, built from its Dockerfile with `webapp/` as the
  build context: `docker build --file apps/<app>/Dockerfile webapp`.
- **One Compose file per app with the whole stack**, which any Docker host runs
  with `docker compose up`: [`apps/web/compose.yaml`](../../webapp/apps/web/compose.yaml)
  and [`apps/cms/compose.yaml`](../../webapp/apps/cms/compose.yaml) (database
  included). `webapp/compose.yaml` runs both for local development.
- **Configuration only through environment variables.** Each app lists its
  production variables in `.env.production.example`; secrets come from the
  platform's secret store, never from files in Git.
- **Health over HTTP and a graceful shutdown**, so any platform can replace a
  container with a rolling update: the new one serves before the old one
  stops, which drains for 10 s on SIGTERM. Each app's `scripts/rolling-update-e2e.ts`
  proves no request is dropped (CI runs both).
- **Migrations at start**, under a database lock, in every process that uses
  the database, so services start in any order. Migrations only add, so the
  previous release keeps working until its replacement is healthy.

## What each service needs

| Service | Image | Port | Health | Runs | State |
| --- | --- | --- | --- | --- | --- |
| Website and proof service (`web`) | `apps/web/Dockerfile`, target `runtime-cms` in production | 3000 | `/health/live`, `/health/ready` | Any number of copies once proof objects are in S3; one while they are on disk | PostgreSQL (`DATABASE_URL`); proof objects in S3 or on disk (`HUSH_DATA_DIR`); the proof-signing key in `HUSH_DATA_DIR` (a persistent volume) |
| CMS API and admin (`cms`) | `apps/cms/Dockerfile` | 3100 | `/health/live`, `/health/ready` | Any number of copies | PostgreSQL (`CMS_DATABASE_URL`); images and backups in S3-compatible buckets |
| CMS scheduler (`cms-scheduler`) | `apps/cms/Dockerfile`, command `bun run cms:scheduler` | none | heartbeat file, see `compose.yaml` | **Exactly one copy** (a single replica, or a CronJob every minute on Kubernetes) | as the API |
| Databases | `postgres:17-alpine`, or the platform's managed PostgreSQL 17 | 5432 | `pg_isready` | one each for web and CMS | a persistent volume, or managed |

Building the production website reads the CMS: it needs the build argument
`HUSH_CMS_URL` (default `https://cms.behu.sh`) and the build secret
`HUSH_CMS_TOKEN` (a read-only CMS token). Publishing a post rebuilds the site;
today the scheduler asks Coolify for that build (`CMS_COOLIFY_*`), so on another
platform this trigger is the one setting to point at its deploy hook.

## On each platform

| Platform | Images | Databases | Rolling updates |
| --- | --- | --- | --- |
| Any Docker host | `docker compose up` per app | in the Compose files | Compose stops, then starts; add a proxy with health checks for zero downtime |
| Coolify (today) | built from Git per resource | Coolify PostgreSQL (`hush-postgres`) for web, the Compose resource's for the CMS | for applications: [web](../../webapp/apps/web/docs/operations/coolify-deployment.md), [CMS](../../webapp/apps/cms/docs/operations/coolify.md) |
| Kubernetes | a Deployment per service (the scheduler as one replica or a CronJob); `kompose convert` turns the Compose files into a starting point | a PostgreSQL operator or a managed database | Deployments roll by default; readiness probe `/health/ready` |
| Fly.io, Railway, Render | each runs a Dockerfile or a registry image | the platform's managed PostgreSQL | built in, using the health path |

## Moving data

- **CMS database**: the scheduler keeps daily `pg_dump` backups in its backup
  bucket; `bun run cms:restore --target-url <new database>` restores the newest
  into the new database ([CMS operations](../../webapp/apps/cms/README.md)).
- **Website database**: `pg_dump` and `pg_restore` between the two PostgreSQL servers.
- **Website proof objects and signing key**: copy `HUSH_DATA_DIR` to the new
  volume. A new signing key is also fine: earlier proofs stay valid through the
  published key set ([signing key rotation](../../webapp/apps/web/docs/operations/coolify-deployment.md#signing-key-rotation)).
- **Images and backups** stay in their buckets; only the credentials move.
