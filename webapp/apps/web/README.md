# hush website and proof service

This directory contains the Vite/React website, browser proof verification and
the Bun/Hono service. It is the `@hush/web` app in the [web workspace](../../README.md) of the
[hush monorepo](../../../README.md).

Use Bun 1.3.9 and the checked-in lockfile:

```sh
cd webapp
bun install --frozen-lockfile
cd apps/web
bun run dev
```

Run the commands below from `webapp/apps/web`.

Vite serves the website at `http://localhost:5173`. The development API runs on
port 3000. The service is needed for Verified Messages, not local dictation.

## Checks

```sh
bun run lint
bun test server
bun run api:check
bun run build
bunx playwright install chromium webkit
bunx playwright test
```

Browser tests launch their own local test service on port 4173. Read
[the proof-recipient contract](docs/user-journeys/proof-recipient.md) before
changing verification, cryptography or private-link behaviour.

Public pages are prerendered through TanStack Router during the Vite build.
See [search and link previews](docs/search-discovery.md) for the shared metadata
catalogue, generated sitemap/llms.txt, Open Graph artwork and Search Console
follow-through. Private proofs remain client-only.

## Deployment

From the monorepo root, the existing local Compose stack remains available:

```sh
docker compose -f webapp/compose.yaml up --build
```

For production, follow [the Coolify guide](docs/operations/coolify-deployment.md)
and the [migration record](../../../docs/monorepo-migration.md). Keep the existing
database and proof-object volumes when changing the source repository.

Original website and service code use **[AGPL-3.0-only](../../../LICENSE)**. Artwork
attribution is in [CREDITS.md](public/art/CREDITS.md); dependencies and assets
retain their own licenses. See [licensing scope and release obligations](../../../LICENSING.md),
including the source offer for modified network versions.
