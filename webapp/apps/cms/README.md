# hush CMS

The `@hush/cms` service manages blog posts for behu.sh: drafts, scheduling,
publishing, revisions and scoped API tokens. Articles are validated and rendered
with [`@hush/article`](../../packages/article/AGENTS.md), the same contract the
website's static build uses. Design: see the PRD linked from
[the web workspace](../../README.md).

## Run locally

Start PostgreSQL, then from this directory:

```sh
export CMS_DATABASE_URL=postgresql://hush:hush@127.0.0.1:5432/cms
export CMS_MEDIA_DIR=.data/media             # images; production uses Cloudflare R2
bun run dev                                   # http://localhost:3100, migrates on start
bun run cms:token --name me --scopes posts:read,posts:write,posts:publish
```

The OpenAPI document is served at `/openapi.json` and committed in
`openapi/hush-cms.json`.

| Command | What it does |
| --- | --- |
| `bun run cms:token` | Creates a token and prints it once |
| `bun run cms:import <dir>` | Imports Markdown articles and their images (the hush-seo format); safe to run again |
| `bun run cms:scheduler` | Long-running: publishes due posts every minute and keeps a daily backup (the `cms-scheduler` service) |
| `bun run cms:publish-due` | Publishes scheduled posts that are due, once |
| `bun run cms:backup` | Backs up the database once and applies retention |
| `bun run cms:restore --target-url <url>` | Restores the newest (or `--key`) backup into a database; the live one needs `--overwrite-live` |
| `scripts/backup-drill.sh` | Proves backups: back up, restore into a fresh database, compare (CI runs it) |
| `bun run db:generate` | Writes a migration after a schema change |

Deployment: [Coolify setup](docs/operations/coolify.md). Journeys:
[CMS journeys](docs/user-journeys/cms.md).

Licensed [AGPL-3.0-only](../../../LICENSE).
