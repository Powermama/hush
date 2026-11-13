# Deploy the CMS on Coolify

The CMS stack is defined in [`webapp/apps/cms/compose.yaml`](../../compose.yaml):
the API (`cms`), its clock (`cms-scheduler`: due posts every minute, a daily
backup) and its own PostgreSQL. Coolify deploys it as one Docker Compose
resource from Git, so nothing about the stack is configured by hand except
secret values. Any Docker Compose host runs the same file; locally,
`webapp/compose.yaml` includes it with `compose.local.yaml` (local password,
volumes instead of R2, a host port).

A Compose resource restarts on deploy instead of rolling over. That is fine for
this internal service: publishing calls retry and the scheduler catches up on
its next tick. The public website stays a Dockerfile application with rolling
updates.

## Create the resource

1. Project `hush` → environment `production` → **New Resource** → **Git
   Repository (with GitHub App)** → `Powermama/hush`, branch `main`.
2. Build pack **Docker Compose**. Base Directory `/webapp/apps/cms`, Docker
   Compose Location `/compose.yaml`. Coolify runs Compose with the Base
   Directory as its project directory, so the build context `../..` then
   resolves to `webapp/`. Name it `hush-cms`.
3. Server `automation`, destination network `hush`, so the website can reach
   the CMS in M2. No domain until the admin UI ships.
4. **Watch Paths**: `webapp/apps/cms/**`, `webapp/packages/**`,
   `webapp/package.json`, `webapp/bun.lock`.

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

## Website deploys and IndexNow

The scheduler keeps behu.sh in step with the CMS (`src/site/deploy.ts`): when
the site serves an older revision than the CMS holds, it asks Coolify to deploy
`hush-website`, whose build pulls the export; once the new revision is live it
submits the changed pages to IndexNow.

1. Coolify **Settings > Advanced**: API access on, **Allowed IPs** only the
   `automation` server's address, so the API answers nothing else.
2. **Keys & Tokens > API tokens**: a token named `hush-cms deploy` with only
   the `deploy` permission, scoped to the `hush-website` resource.
3. In hush-cms, locked and runtime only: `CMS_SITE_URL`, `CMS_COOLIFY_URL`,
   `CMS_COOLIFY_TOKEN`, `CMS_COOLIFY_WEBSITE_UUID` and `CMS_INDEXNOW_KEY` (the
   key the website serves at `/<key>.txt`).
4. A read-only CMS token for the website build:
   `bun run cms:token --name website-build --scopes posts:read`, stored in
   `hush-website` as described in the website's deployment guide.

## After the first deploy

1. Create the owner's token in the `cms` container's terminal:
   `bun run cms:token --name owner --scopes posts:read,posts:write,posts:publish --days 90`.
2. Check the `cms-scheduler` logs for "Backed up the CMS database".
3. Restore drill: create a scratch database in `cms-postgres`
   (`createdb -U cms cms_restore`), run
   `bun run cms:restore --target-url postgresql://cms:<password>@cms-postgres:5432/cms_restore`
   in the `cms` container, compare `select count(*) from posts`, then drop it.
   Repeat after any change to the backup code and at least every quarter.
