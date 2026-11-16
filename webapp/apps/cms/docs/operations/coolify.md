# Deploy the CMS on Coolify

The CMS stack is defined in one file, [`webapp/apps/cms/compose.yaml`](../../compose.yaml):
the API (`cms`), its clock (`cms-scheduler`: due posts every minute, a daily
backup) and its own PostgreSQL. Any Docker Compose host runs that file as it is
([deploy anywhere](../../../../../docs/reference/deploy-anywhere.md)); locally, `webapp/compose.yaml` includes
it with `compose.local.yaml` (local password, volumes instead of R2, a host port).

On Coolify the stack is three resources, because Coolify replaces only
applications with a rolling update and stops every service of a Docker Compose
resource on each deploy ([Coolify: rolling updates](https://coolify.io/docs/applications/deployments/rolling-updates)):

| Resource | What | Deploys |
| --- | --- | --- |
| `hush-cms-api` | Dockerfile application: the API and the admin at cms.behu.sh | Rolling update on every push: the new container passes `/health/ready`, then the old one drains (10 s) and stops. `scripts/rolling-update-e2e.ts` proves no request is dropped (CI runs it). |
| `hush-cms-scheduler` | Dockerfile application: the same image, start command `bun run cms:scheduler`, no domain | Rolling update; for a moment two schedulers run, which is safe (every step is idempotent). |
| `hush-cms` | Docker Compose resource from [`compose.coolify.yaml`](../../compose.coolify.yaml): PostgreSQL alone, with its volume | Only when that file changes, so code deploys never restart the database. |

`compose.coolify.yaml` holds exactly the PostgreSQL service of `compose.yaml`
(`tests/compose.test.ts` keeps them in step). The API and the scheduler apply
migrations at start under one lock and answer `/health/ready` on port 3100, so
they start in any order. The website's build reads the CMS at `https://cms.behu.sh`.

## Create the resources

The Compose resource `hush-cms` (PostgreSQL):

1. Project `hush` → environment `production` → **New Resource** → **Git
   Repository (with GitHub App)** → `Powermama/hush`, branch `main`.
2. Build pack **Docker Compose**. Base Directory `/webapp/apps/cms`, Docker
   Compose Location `/compose.coolify.yaml`. Name it `hush-cms`.
3. Server `automation`, destination network `hush`, and under **Advanced >
   Predefined network** connect to the destination network, so the
   applications reach the database as `cms-postgres-<hush-cms uuid>`. No domain.
4. **Watch Paths**: `webapp/apps/cms/compose.coolify.yaml`.

The applications `hush-cms-api` and `hush-cms-scheduler`, each:

1. **New Resource** → **Git Repository (with GitHub App)** → `Powermama/hush`,
   branch `main`, build pack **Dockerfile**, Base Directory `/webapp`,
   Dockerfile Location `/apps/cms/Dockerfile`, port `3100`, server
   `automation`, destination network `hush`.
2. No **Ports Mappings**, no **Custom Container Name** and no custom IP: each
   makes Coolify stop the old container first instead of rolling over.
3. **Health check**: path `/health/ready`, port `3100`, interval 5 s, retries 3.
4. **Environment variables**: the variables of [Secrets](#secrets) and the
   sections below, plus `CMS_DATABASE_URL=postgresql://cms:<hush-cms's SERVICE_PASSWORD_64_CMSPOSTGRES>@cms-postgres-<hush-cms uuid>:5432/cms`,
   all locked and runtime only.
5. **Watch Paths**: `webapp/apps/cms/**`, `webapp/apps/cms-admin/**` (the image
   includes the admin), `webapp/packages/**`, `webapp/package.json`,
   `webapp/bun.lock`. Auto deploy on push, as the website.

`hush-cms-api` gets the domain `https://cms.behu.sh`. `hush-cms-scheduler`
gets the start command `bun run cms:scheduler` and no domain.

### Move from one Compose resource (once)

Production ran all three services in `hush-cms` from `compose.yaml` until
2026-11-16. To move without losing data or the domain:

1. In `hush-cms`, connect to the destination network and redeploy (the last
   restart of the API there).
2. Create `hush-cms-api` and `hush-cms-scheduler` as above and deploy them.
   Check that both are healthy.
3. Remove the domain `cms.behu.sh` from the `cms` service of `hush-cms` and add
   it to `hush-cms-api`.
4. Set `hush-cms`'s Docker Compose Location to `/compose.coolify.yaml` and its
   watch path, and redeploy: its `cms` and `cms-scheduler` containers go away,
   PostgreSQL keeps its volume.
5. Sign in at cms.behu.sh, run `hush-cms auth status`, and check the
   scheduler's logs for its next tick.

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

Check after changes: from the `hush-cms-scheduler` container a request to
`http://172.16.0.2:8000/api/v1/applications/<website uuid>` with the deploy
token answers "Missing required permissions: read" (the IP is allowed, the
token is limited), and from the internet every `/api` path answers 403.

## The admin at cms.behu.sh

The CMS serves its admin (`apps/cms-admin`, built into the image) on its own
origin. Sign-in is a GitHub OAuth App with PKCE; only listed GitHub user ids get
a session.

1. **GitHub > Settings > Developer settings > OAuth Apps > New**: name
   `hush CMS`, homepage `https://cms.behu.sh`, callback
   `https://cms.behu.sh/auth/github/callback`, wildcard matching off, device
   flow off, expiring user tokens on. Generate a client secret.
2. **Cloudflare DNS**: `cms.behu.sh`, A, the app server's address, proxied.
3. **Coolify, hush-cms-api > General**: domain `https://cms.behu.sh` (Traefik
   routes to the container's port 3100; nothing is published on the host).
4. **Environment variables**, runtime only: `CMS_PUBLIC_URL=https://cms.behu.sh`,
   `CMS_ADMIN_GITHUB_IDS` (numeric ids, `https://api.github.com/users/<login>`
   shows `id`), `CMS_GITHUB_CLIENT_ID`, and `CMS_GITHUB_CLIENT_SECRET` locked.
   Copy the secret from GitHub straight into Coolify.
5. Redeploy, open `https://cms.behu.sh` and sign in. A GitHub account outside
   the list gets "This GitHub account may not use the hush CMS."

Protect the allowed GitHub accounts with a passkey or two-factor
authentication: the admin inherits their sign-in.

## After the first deploy

1. Connect the CLI on the owner's Mac with `hush-cms auth login` and approve
   its code at cms.behu.sh/device ([CLI guide](../../../cms-cli/README.md)).
   `bun run cms:token` in the `cms` container is only for tokens no person
   signs in for, such as the website build's read token (step 7 above).
2. Check the `cms-scheduler` logs for "Backed up the CMS database".
3. Restore drill: create a scratch database in `cms-postgres`
   (`createdb -U cms cms_restore`), run
   `bun run cms:restore --target-url postgresql://cms:<password>@cms-postgres:5432/cms_restore`
   in the `cms` container, compare `select count(*) from posts`, then drop it.
   Repeat after any change to the backup code and at least every quarter.
