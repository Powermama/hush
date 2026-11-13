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
bun run dev                                   # http://localhost:3100, migrates on start
bun run cms:token --name me --scopes posts:read,posts:write,posts:publish
```

The OpenAPI document is served at `/openapi.json` and committed in
`openapi/hush-cms.json`.

| Command | What it does |
| --- | --- |
| `bun run cms:token` | Creates a token and prints it once |
| `bun run cms:publish-due` | Publishes scheduled posts that are due (a Coolify task runs it every minute) |
| `bun run db:generate` | Writes a migration after a schema change |

Deployment: [Coolify setup](docs/operations/coolify.md). Journeys:
[CMS journeys](docs/user-journeys/cms.md).

Licensed [AGPL-3.0-only](../../../LICENSE).
