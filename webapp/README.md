# hush web workspace

A [Bun workspace](https://bun.sh/docs/install/workspaces) with one lockfile.
Deployable apps live in `apps/`, shared libraries in `packages/`.

| Path | Package | What it is |
| --- | --- | --- |
| [`apps/web`](apps/web/README.md) | `@hush/web` | The Vite/React website, browser proof verification and the Bun/Hono proof service |
| [`apps/cms`](apps/cms/README.md) | `@hush/cms` | The blog CMS: posts, scheduling, revisions and the admin API, with its own PostgreSQL |
| [`packages/article`](packages/article/AGENTS.md) | `@hush/article` | The article contract and renderer: front matter, content rules, Markdown to HTML, authors and blog vocabulary |

Install once at the workspace root, then work inside an app:

```sh
cd webapp
bun install --frozen-lockfile
bun run dev            # the website and its API, same as in apps/web
```

Each app has its own Dockerfile, built from this directory so it can use shared
packages: `docker build --file apps/web/Dockerfile .`. Dependency `overrides`
belong in this directory's `package.json`; Bun ignores them in workspace members.

Licensed [AGPL-3.0-only](../LICENSE); see [LICENSING.md](../LICENSING.md).
