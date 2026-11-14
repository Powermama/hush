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
the site serves an older revision than the CMS holds, it asks Coolify for a
forced build of `hush-website` (a normal deploy reuses the image of the current
commit and skips the build), which pulls the export; once the new revision is live it
submits the changed pages to IndexNow.

The CMS reaches Coolify's API only over a private network, never the internet:

1. **Hetzner private network** `hush-private`, `172.16.0.0/16` (subnet
   `172.16.0.0/24`, zone eu-central): the Coolify server is `172.16.0.2`, the
   app server `172.16.0.3`. Not `10.x`: Coolify gives Docker the `10.0.0.0/8`
   pools, and the app server's Docker uses `172.17` to `172.31`.
2. **Hetzner Cloud Firewall** `coolify-host` on the Coolify server: 80 and 443
   only from Cloudflare's ranges (https://www.cloudflare.com/ips/), SSH and
   ICMP; 8000, 6001 and 6002 are closed publicly (the dashboard, realtime and
   terminal run through 443). Cloud firewalls filter before Docker, which
   bypasses UFW; private network traffic is not filtered.
3. Coolify **Settings > Advanced**: API access on, **Allowed IPs** `172.16.0.3`.
4. **Cloudflare custom rule** "Block public Coolify API" on the Coolify domain:
   `(http.host eq "admin.decentralfreedom.com" and starts_with(lower(url_decode(http.request.uri.path)), "/api"))`
   with action Block, so the API is unreachable through the public hostname.
5. **Keys & Tokens > API tokens**: `hush-cms deploy`, only the `deploy`
   permission, scoped to the `hush-website` resource, one year. Renew it before
   it expires; the scheduler turns unhealthy when deploys fail.
6. In hush-cms, locked and runtime only: `CMS_SITE_URL=https://behu.sh`,
   `CMS_COOLIFY_URL=http://172.16.0.2:8000`, `CMS_COOLIFY_TOKEN`,
   `CMS_COOLIFY_WEBSITE_UUID` and `CMS_INDEXNOW_KEY` (the key the website
   serves at `/<key>.txt`).
7. A read-only CMS token for the website build:
   `bun run cms:token --name website-build --scopes posts:read`, stored in
   `hush-website` as described in the website's deployment guide.

Check after changes: from the `cms` container a request to
`http://172.16.0.2:8000/api/v1/applications/<website uuid>` with the deploy
token answers "Missing required permissions: read" (the IP is allowed, the
token is limited), and from the internet every `/api` path answers 403.

## After the first deploy

1. Create the owner's token in the `cms` container's terminal:
   `bun run cms:token --name owner --scopes posts:read,posts:write,posts:publish --days 90`.
2. Check the `cms-scheduler` logs for "Backed up the CMS database".
3. Restore drill: create a scratch database in `cms-postgres`
   (`createdb -U cms cms_restore`), run
   `bun run cms:restore --target-url postgresql://cms:<password>@cms-postgres:5432/cms_restore`
   in the `cms` container, compare `select count(*) from posts`, then drop it.
   Repeat after any change to the backup code and at least every quarter.
