# Deploy hush on Coolify

Production runs the website as the Coolify Dockerfile application `hush-website` (rolling updates, see [Zero-downtime deployments](#zero-downtime-deployments)) next to the Coolify PostgreSQL database `hush-postgres`. The container persists encrypted proof objects, applies database migrations before startup, and reports readiness through `/health/ready`. Run this guide's shell commands from `webapp/`.

The same image runs locally with the website and its database from `apps/web/compose.yaml`, included by the workspace's `compose.yaml` together with the CMS:

```sh
docker compose up --build
```

Local hush is then available at `http://127.0.0.1:3000`. Development signing keys, PostgreSQL data, and encrypted proof objects remain in local named volumes. The existing `bun run dev` workflow remains available for fast frontend and API iteration.

The release manifest in `shared/releases.ts` points website download buttons to
the exact immutable DMG for the current build. Each release increments its
version or build identity before publishing. The stable `hush-latest.dmg` alias
remains a compatibility pointer only and is never used by the website. The
update subdomain points directly to the public Cloudflare R2 bucket and does not
route large artifacts through Coolify.

When the manifest is empty, download actions show availability information
instead of linking to an old build. Add the next release only after its
notarization, installation check, and public artifact verification are complete.
The manifest is the only source for download URLs; Compose does not override it.

Configure one Cloudflare Cache Rule for the mutable release pointers:

```text
Hostname equals updates.behu.sh
AND URI Path is in
  /downloads/hush-latest.dmg
  /alpha/appcast.xml
```

Set **Cache eligibility** to **Bypass cache**. The publisher also writes these
two objects with `Cache-Control: no-store`. Versioned DMGs and Sparkle archives
keep one-year immutable caching. This separation lets the stable button and
update feed change immediately without giving up CDN caching for large release
artifacts.

If port 3000 is already used by the native development server, choose another host port without changing the container contract:

```sh
HUSH_COMPOSE_PORT=4300 docker compose up --build
```

## 1. Create the service

For a new installation, create the Coolify PostgreSQL database `hush-postgres` and the Dockerfile application `hush-website` from `Powermama/hush`, configured as in [Coolify settings for `hush-web`](#coolify-settings-for-hush-web): base directory `/webapp`, Dockerfile location `/apps/web/Dockerfile`, port `3000`, domain `https://behu.sh`. A Docker Compose resource is not used for the website, because Coolify cannot roll Compose resources over without downtime. For the existing installation, the [migration record](../../../../../docs/monorepo-migration.md) explains how the database, keys and volumes were preserved.

Select `main` and `HEAD` in Git Source. Keep `main` protected by the required
pull-request checks; merge tested changes before deploying them.

Do not add a custom Docker network. Coolify attaches the Compose services to its managed network and routes the domain to the exposed web port.

No update-bucket credentials belong in Coolify. Release automation uploads to
R2 through its private S3 endpoint. The web build contains only public,
versioned download URLs.

### Automatic website deployments

Automatic deployment is configured in Coolify and its Git integration, not in
the Compose file. Follow Coolify's
[automatic-deployment guide](https://coolify.io/docs/applications/deployments/automatic-deployments):

1. Confirm the connected GitHub App can access `Powermama/hush`. A new repository
   with an old name still has a new repository identity; recheck its installation
   access after a migration.
2. In **Advanced > Deployment > Auto deploy**, select **Deploy on push
   (webhooks)**. Pull-request previews are separate from production.
3. In **General > Build > Watch Paths**, save `webapp/**`. This pattern is relative
   to the repository root, even though the build base directory is `/webapp`.
   Website changes, including deployment documentation, trigger a deployment;
   native-app and root README changes do not.
4. Merge a website change and confirm **Webhook** and the merged commit in
   **Deployment Logs**. A branch push before merge must not deploy production.
5. Confirm `/health/ready` and the changed public page before calling the update
   live. Also check that a root documentation-only merge does not deploy.

Use one pattern per line if the website later depends on more shared paths.
Manual redeployments bypass the watch-path filter. This setup uses the existing
GitHub App webhook and Coolify server; it needs no additional deployment runner,
personal access token, or scheduled job.

## 2. Configure DNS

Point the `A` record for `behu.sh` to the public IPv4 address of the Coolify application server. Add an `AAAA` record only if the server has working public IPv6. Remove conflicting records, wait for DNS propagation, then let Coolify provision HTTPS.

`updates.behu.sh` is intentionally separate. Connect that hostname from the
`hush` bucket under **R2 > Settings > Public access > Custom Domains**.
Cloudflare creates its DNS record automatically. Do not add it as a Coolify
domain or point it at the Coolify server.

### Cloudflare in front of Coolify

Use these settings when Cloudflare manages `behu.sh`:

1. Keep the `A` or `AAAA` record Proxied with the orange cloud.
2. Add `https://behu.sh` as the domain for the Coolify `web` service on port 3000 and wait until the Coolify origin certificate is valid.
3. Set Cloudflare SSL/TLS encryption mode to Full (strict). Do not use Flexible mode.
4. Enable Always Use HTTPS.
5. Keep Cloudflare's standard cache behavior. hush sends one-year immutable caching only for fingerprinted `/assets/` files, five-minute caching for public discovery files, and `no-store` for private verifier pages.
6. Do not create a Cache Everything rule for `behu.sh`. If account-wide cache rules already exist, add a higher-priority bypass for `/v1/*`, `/p/*`, `/health/*`, and `/openapi.json`.

Cloudflare and Coolify never receive URL fragments. The `#k=` proof key remains browser-only even while the hostname is proxied.

For stronger origin isolation, allow Cloudflare IP ranges at the server firewall or configure Authenticated Origin Pulls after confirming Coolify health checks and certificate renewal still reach the origin. Until then, do not publish a second DNS-only hostname pointing at the same origin.

## 3. Automatic secrets

No secret needs to be generated or pasted before the first deployment.

- Coolify generates `SERVICE_PASSWORD_64_POSTGRES` once and keeps it stable across deployments.
- On the very first production start, set `HUSH_ALLOW_SERVICE_KEY_BOOTSTRAP=1` once. hush then generates a P-256 proof-signing key and atomically stores it at `/app/data/service-key.json` in the persistent data volume. Remove the variable after that start.
- Later deployments reuse the same signing key automatically.
- In production, hush refuses to start when the key file is missing and bootstrapping is not enabled. A mis-mounted or empty volume therefore fails the deployment loudly; it never silently mints a new identity that would invalidate existing proofs. During a rolling update the old instance keeps serving.

Back up the signing key as described in [Signing key backup](#signing-key-backup) before publishing real proofs. Losing it loses the signing identity used by existing proofs.

For external key management, generate a key locally and provide the two output values as runtime-only Coolify secrets:

```sh
bun run key:generate hush-production-1
```

Set `HUSH_SERVICE_KEY_ID` and `HUSH_SERVICE_PRIVATE_JWK`, mark the private JWK as a secret, and disable Build Variable. An environment key takes precedence over the volume-managed key. Do not replace either key after publishing proofs unless a deliberate signing-key migration is implemented.

## 4. Deploy

The web container starts only after PostgreSQL becomes healthy. At startup it applies pending migrations and then starts hush. The container health check calls:

```text
GET /health/ready
```

Successful deployment checks:

```sh
curl --fail https://behu.sh/health/live
curl --fail https://behu.sh/health/ready
curl --fail https://behu.sh/robots.txt
curl --fail https://behu.sh/llms.txt
curl --fail https://behu.sh/
```

Both proof URL forms are supported by the same service:

- Public short link: `https://behu.sh/Ab3dE7#k=...`
- Internal compatibility route: `https://behu.sh/s/Ab3dE7#k=...`

The redirect never receives or returns the fragment key.

## Backups

What production keeps, and what a restore needs:

| Data | Where | Backup |
| --- | --- | --- |
| Proof metadata, installations, aliases | `hush-postgres` (PostgreSQL 17) | Daily to R2, see below |
| Proof-signing key | `/app/data/service-key.json` in `hush-website`'s volume | Separately, see below. **Losing it is the one unrecoverable failure.** |
| Encrypted proof blobs | `/app/data/objects` in the same volume | None: they expire within 90 days and cannot be decrypted without the recipient's link |

A lost database is survivable: each Mac enrolls again automatically when the
service no longer knows its installation, and only proofs that are still live
stop resolving. A lost signing key is not: production refuses to start without
it, and a new key cannot vouch for receipts signed by the old one.

### Database backups

`hush-postgres` → **Backups**: schedule `15 3 * * *` (UTC), database `hush`, S3
on with the destination `hush-proof-backups (R2)` only, local copy deleted
after upload, S3 retention 7 days, alert after 2 days without a backup.

The destination (**Storages** → `hush-proof-backups (R2)`) uses an R2 Account
API token with Object Read & Write on the bucket `hush-proof-backups` only,
region `auto`, path-style URLs, TLS verification on. The bucket is non-public
and its lifecycle rule `expire-after-9-days` deletes objects after 9 days, which
bounds the privacy policy's 9-day promise even if Coolify's cleanup fails.

**Restore drill** (after any change to backups, and at least every quarter):
create a scratch PostgreSQL 17 database on the `automation` server, use
**Import Backup** to restore the newest file from `hush-proof-backups`, and
compare `select count(*) from proofs` and `select count(*) from installation_keys`
with production. Then delete the scratch database. Never import into
`hush-postgres` itself unless recovering from a loss, and follow
[Backups and restores](../proof-retention.md#backups-and-restores) before
serving restored proofs.

### Signing key backup

Keep one copy of the key **outside the server and outside the data buckets**,
encrypted, so a lost volume or a compromised bucket cannot take it with them.
Do this once now, and again whenever the key changes:

1. Coolify → `hush-website` → **Terminal**: run `sha256sum /app/data/service-key.json`
   and note the hash, then `cat /app/data/service-key.json`.
2. Copy the JSON into a password manager item (for example "hush proof-signing
   key, hush-production-1") with the hash in its notes. Never paste it into Git,
   chat, tickets, email or an R2 bucket. Clear the terminal afterwards.
3. Restore: compare the SHA-256, then put the file back unchanged at
   `/app/data/service-key.json` in the volume (owner `bun`, mode `600`). The
   file is `{ "id": ..., "privateJwk": {...} }`; to use runtime secrets instead,
   set `HUSH_SERVICE_KEY_ID` to its `id` and the secret `HUSH_SERVICE_PRIVATE_JWK`
   to its `privateJwk` object (see [Automatic secrets](#3-automatic-secrets)).
   Either way the service starts with the same identity.

If external key management is enabled, the key already lives outside the
server; keep its password-manager copy the same way. A deployment is not
recoverable from the Git repository alone.

## Optional external storage

For multiple web replicas, replace the local encrypted-object volume with S3-compatible storage and configure `HUSH_S3_BUCKET`, `HUSH_S3_REGION`, `HUSH_S3_ENDPOINT`, `HUSH_S3_ACCESS_KEY_ID`, and `HUSH_S3_SECRET_ACCESS_KEY`. PostgreSQL remains the source of truth. The included single-web-service stack does not require S3.

## Zero-downtime deployments

Goal: a deployment never fails a visitor's or the Mac app's request. A Docker
Compose resource cannot reach that goal on Coolify: "Rolling updates are not
supported for Docker Compose applications"
([Coolify rolling updates](https://coolify.io/docs/applications/deployments/rolling-updates)).
Compose stops the old web container before the new one is ready, which caused
the brief HTTP 503 observed while PR #17 deployed on 12 November 2026.

The target topology separates concerns:

| Resource | Coolify type | Owns |
| --- | --- | --- |
| `hush-web` | Application, Dockerfile build pack, base directory `/webapp` | The stateless web process; the encrypted-object volume at `/app/data` |
| `hush-postgres` | Database, PostgreSQL 17 | Proof metadata and aliases, with Coolify's database backups |

### Platform-neutral runtime contract

Zero downtime depends on the application, not on one host. Any platform that
starts a replacement, waits for readiness and then sends `SIGTERM` (Coolify,
Docker Swarm, Kubernetes, Fly.io) works without code changes:

| Contract | Behaviour |
| --- | --- |
| `GET /health/live` | 200 while the process runs, including while draining. Use for liveness only. |
| `GET /health/ready` | 200 only when the instance is not draining and PostgreSQL answers within 2 seconds; otherwise 503. Never cached. Use for readiness and routing. During a deploy the proxy may still send a few requests to the draining instance, so `https://behu.sh/health/ready` can briefly answer 503 while every page succeeds. Point external uptime monitors at `/health/live` or a page, not at `/health/ready`. |
| `SIGTERM` | Report not-ready and keep serving for `HUSH_SHUTDOWN_DRAIN_MS` (default 10000), answering with `Connection: close` so the proxy stops reusing keep-alive connections to this instance. Then wait (at most 10 seconds) for in-flight requests, close every remaining connection at once, close the database and exit 0. Leaving idle keep-alive connections open made requests sent on them hang until they timed out. |
| Configuration | Environment variables only. No host port, container name or IP is required. |
| Migrations | Applied at start under a PostgreSQL advisory lock, so concurrent starts never race. |
| Background cleanup | Idempotent; two instances may run it during an overlap. |
| Shared volume | Object writes are atomic (temporary file, then rename). |
| `HUSH_READ_ONLY=1` | Proof writes return 503 with `Retry-After: 300`; pages and proof reads keep working. Used during data moves. |

**Migrations must stay additive.** The previous release keeps serving from the
new schema until its replacement is healthy. Add tables, nullable columns and
indexes freely. Remove or rename something only in a later release, after no
running version uses it.

### Coolify settings for `hush-web`

1. **General**: build pack Dockerfile, base directory `/webapp` (the workspace root, so shared packages are in the build context), Dockerfile location `/apps/web/Dockerfile`, port `3000`, domain `https://behu.sh`. Leave **Ports Mappings** empty; a published host port disables rolling updates.
2. **Advanced**: keep the default container naming. Do not set a custom container name or IP; each disables rolling updates.
3. **Health Check**: enable it with path `/health/ready`, port `3000`, interval 5 seconds, timeout 2 seconds, retries 3, start period 10 seconds. The dashboard check replaces the image's slower `HEALTHCHECK`.
4. **Advanced > Operations > Stop Grace Period**: 30 seconds (Coolify's default). The drain (10 seconds) plus in-flight requests must finish well inside it.
5. **Container Labels**: keep **Managed by Coolify**. No retry middleware is needed: the end-to-end check below runs with Coolify's generated labels and no retry, and drops no requests. Hand-edited labels would stop following domain changes.
6. **Environment Variables** (runtime only): `NODE_ENV=production`, `PORT=3000`, `HUSH_PUBLIC_BASE_URL=https://behu.sh`, `HUSH_DATA_DIR=/app/data`, `HUSH_SERVICE_KEY_ID`, and `DATABASE_URL` from the `hush-postgres` resource's internal connection URL.
7. **Persistent Storage**: one volume mounted at `/app/data`.
8. Automatic deployment settings stay as in "Automatic website deployments" above.

### Verify the contract before every infrastructure change

```sh
bun scripts/rolling-update-e2e.ts
```

The script builds the production image and runs PostgreSQL, Traefik and the web
service in local Docker. Traefik routes with labels like Coolify's and no retry
middleware; the rolling replacement waits for health, then five seconds, then
stops the old container, as Coolify's deployment log shows. It replays both
replacement models under continuous load from eight concurrent clients. The Compose-style control must drop
requests, which proves the probe detects outages. The rolling update must drop
none and keep the signing key unchanged. CI runs the same check whenever the
web service changes.

### Migrate the existing Compose installation

**Completed on 12 November 2026.** Production now runs `hush-website`
(Dockerfile application) and `hush-postgres` (PostgreSQL 17) on a dedicated
`hush` Docker network on the `automation` server. Before cutover the signing
key's SHA-256 matched in the new volume and every table had identical row
counts in both databases. The previous Compose resource `hush-web` is stopped,
not deleted, with its volumes as the rollback; the backup is in
`/root/hush-backup-20261112-1815` on that server. In a redeploy under load after the
cutover, one request timed out exactly when the old instance's drain ended,
which led to closing keep-alive connections during the drain (see the runtime
contract). The local end-to-end check did not reproduce that timeout, so
production redeploys are measured as well. Because nobody depended on the site
yet, the cutover used a short planned window instead of a temporary domain.

The steps below remain the procedure for a future migration. Run them once, in order. Every step has a check; stop at the first failing check.
Keep the old Compose resource and its volumes until the new setup has served
production for at least a week.

1. **Back up.** In the Compose resource's terminal or on the server:
   `pg_dump -Fc` of the `hush` database, and a `tar` of the `hush_objects`
   volume. Copy both off the server and record their SHA-256 checksums. Record
   the SHA-256 of `/app/data/service-key.json`.
2. **Create `hush-postgres`** (PostgreSQL 17) in the same project and network.
   Restore the dump with `pg_restore --no-owner`. Compare row counts of every
   table with the source.
3. **Create `hush-web`** with the settings above, but on a temporary domain
   (for example `https://next.behu.sh`). Add the persistent storage, then copy
   the `hush_objects` contents into the new volume, preserving ownership for the
   `bun` user (UID 1000). Do not set `HUSH_ALLOW_SERVICE_KEY_BOOTSTRAP`: if the
   copy is wrong, the deployment fails instead of minting a new key.
4. **Verify on the temporary domain**: `/health/ready` is 200; the key file's
   SHA-256 matches step 1; a known private proof opens and verifies in its
   recipient's browser; the homepage, `/verified-messages` and `/releases`
   render.
5. **Rehearse rolling updates** on the temporary domain: redeploy three times
   while polling it every 200 milliseconds. Require zero non-2xx responses.
6. **Cut over.**
   1. Set `HUSH_READ_ONLY=1` on the Compose resource and redeploy it. Proof
      publishing pauses; every page stays up.
   2. Take a final `pg_dump` and restore it into `hush-postgres`; copy any
      objects created since step 3.
   3. Move `https://behu.sh` from the Compose resource to `hush-web`, keeping
      the temporary domain until the switch is verified.
   4. Verify `/health/ready`, a proof, and the pages on `https://behu.sh`.
   5. Stop (do not delete) the Compose resource.
7. **Rollback**: move the domain back to the Compose resource, remove
   `HUSH_READ_ONLY`, and redeploy it. Its database and volume are untouched
   until the final cleanup.
