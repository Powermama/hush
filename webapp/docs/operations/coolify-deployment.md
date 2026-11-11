# Deploy hush on Coolify

The production stack is defined in `webapp/docker-compose.coolify.yaml` from the monorepo root. It runs the hush web service and PostgreSQL, persists encrypted proof objects and database records, applies database migrations before startup, and reports readiness through `/health/ready`. Run this guide's shell commands from `webapp/`.

The same container and topology can be exercised locally with the standard `compose.yaml`:

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

For a new installation, create a resource from `Powermama/hush` and select Docker Compose as the build pack. For the existing production installation, update its source configuration in place and follow the [migration record](../../../docs/monorepo-migration.md) to preserve the database, keys and volumes.

- Base directory: `/webapp`
- Docker Compose location: `/docker-compose.coolify.yaml`
- Domain: `https://behu.sh`
- Service and port: `web:3000`

Coolify resolves the Compose location and build context from the base directory.
These settings follow its [Docker Compose documentation](https://coolify.io/docs/applications/builds/docker-compose).

Select the intended Git branch in Coolify's resource settings. Automatic
deployment on push is configured in Coolify and its Git integration, not in the
Compose file. After pushing, verify the deployed page and `/health/ready` before
calling the website update live.

Do not add a custom Docker network. Coolify attaches the Compose services to its managed network and routes the domain to the exposed web port.

No update-bucket credentials belong in Coolify. Release automation uploads to
R2 through its private S3 endpoint. The web build contains only public,
versioned download URLs.

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
- hush generates a P-256 proof-signing key on first startup and atomically stores it at `/app/data/service-key.json` in the persistent `hush_objects` volume.
- Later deployments reuse the same signing key automatically.

Back up the `hush_objects` volume before publishing real proofs. Losing that volume loses the signing identity used by existing proofs.

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

## Persistence and backups

- `hush_postgres` stores proof metadata and aliases.
- `hush_objects` stores encrypted proof blobs under `/app/data`.
- The generated signing JWK is stored in `hush_objects` unless an external runtime secret overrides it.

Back up both named volumes. If external key management is enabled, back up that signing key separately. A deployment is not recoverable from the Git repository alone.

## Optional external storage

For multiple web replicas, replace the local encrypted-object volume with S3-compatible storage and configure `HUSH_S3_BUCKET`, `HUSH_S3_REGION`, `HUSH_S3_ENDPOINT`, `HUSH_S3_ACCESS_KEY_ID`, and `HUSH_S3_SECRET_ACCESS_KEY`. PostgreSQL remains the source of truth. The included single-web-service stack does not require S3.
