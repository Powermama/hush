# hush web workspace guidance

- Each app or package has its own `AGENTS.md`; read the one you are changing.
- Install from this directory (`bun install --frozen-lockfile`); run an app's
  commands from its own directory, for example `webapp/apps/web`.
- Apps go in `apps/`, shared code in `packages/` with explicit `exports`. An app
  never imports another app's files; share through a package instead.
- Dependency `overrides` live only in this directory's `package.json`.
- Build images from this directory: `docker build --file apps/<app>/Dockerfile .`.
