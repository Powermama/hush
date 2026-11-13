# Deploy the CMS on Coolify

The CMS stack is defined in [`webapp/docker-compose.cms.yaml`](../../../../docker-compose.cms.yaml):
the API (`cms`), its clock (`cms-scheduler`: due posts every minute, a daily
backup) and its own PostgreSQL. Coolify deploys it as one Docker Compose
resource from Git, so nothing about the stack is configured by hand except
secret values. Any Docker Compose host runs the same file.

A Compose resource restarts on deploy instead of rolling over. That is fine for
this internal service: publishing calls retry and the scheduler catches up on
its next tick. The public website stays a Dockerfile application with rolling
updates.

## Create the resource

1. Project `hush` → environment `production` → **New Resource** → **Git
   Repository (with GitHub App)** → `Powermama/hush`, branch `main`.
2. Build pack **Docker Compose**. Base Directory `/webapp`, Docker Compose
   Location `/docker-compose.cms.yaml`. Name it `hush-cms`.
3. Server `automation`, destination network `hush`, so the website can reach
   the CMS in M2. No domain until the admin UI ships.
4. **Watch Paths**: `webapp/apps/cms/**`, `webapp/packages/**`,
   `webapp/docker-compose.cms.yaml`, `webapp/package.json`, `webapp/bun.lock`.

## Secrets

Coolify generates `SERVICE_PASSWORD_64_CMSPOSTGRES`. Set the rest under
**Environment Variables**, each **locked** and **not available at build time**;
the names are listed in [`apps/cms/.env.production.example`](../../.env.production.example):

| Variables | Source |
| --- | --- |
| `CMS_S3_ENDPOINT`, `CMS_S3_ACCESS_KEY_ID`, `CMS_S3_SECRET_ACCESS_KEY` | Cloudflare R2 → Manage API tokens → a token with Object Read & Write on **`hush-blog-media` only** |
| `CMS_BACKUP_S3_ENDPOINT`, `CMS_BACKUP_S3_ACCESS_KEY_ID`, `CMS_BACKUP_S3_SECRET_ACCESS_KEY` | A second token with Object Read & Write on **`hush-cms-backups` only** (a private bucket) |

The endpoint is `https://<account-id>.r2.cloudflarestorage.com`. Never use the
app-update bucket `hush`, which ships the Mac app. Copy each value straight from
Cloudflare into Coolify; it must not pass through Git, `.env` files or chat.

## After the first deploy

1. Create the owner's token in the `cms` container's terminal:
   `bun run cms:token --name owner --scopes posts:read,posts:write,posts:publish --days 90`.
2. Check the `cms-scheduler` logs for "Backed up the CMS database".
3. Restore drill: create a scratch database in `cms-postgres`
   (`createdb -U cms cms_restore`), run
   `bun run cms:restore --target-url postgresql://cms:<password>@cms-postgres:5432/cms_restore`
   in the `cms` container, compare `select count(*) from posts`, then drop it.
   Repeat after any change to the backup code and at least every quarter.
