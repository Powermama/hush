# syntax=docker/dockerfile:1
# Built from the workspace root: docker build --file apps/cms/Dockerfile .
# The CMS serves its admin (apps/cms-admin), built in the first stage.
FROM oven/bun:1.3.9-alpine AS admin

WORKDIR /app
COPY --parents package.json bun.lock apps/*/package.json packages/*/package.json ./
RUN bun install --frozen-lockfile --filter @hush/cms-admin
COPY packages/article ./packages/article
COPY apps/cms/openapi ./apps/cms/openapi
WORKDIR /app/apps/cms-admin
COPY apps/cms-admin ./
RUN bun run build

FROM oven/bun:1.3.9-alpine

# pg_dump and pg_restore for backups, matching the PostgreSQL 17 server.
RUN apk add --no-cache postgresql17-client

WORKDIR /app
ENV NODE_ENV=production \
    PORT=3100

# A frozen install checks the lockfile against every workspace, so copy each
# workspace manifest (COPY --parents keeps their paths).
COPY --parents package.json bun.lock apps/*/package.json packages/*/package.json ./
RUN bun install --frozen-lockfile --production --filter @hush/cms
COPY packages/article ./packages/article
WORKDIR /app/apps/cms
COPY apps/cms/src ./src
COPY --from=admin /app/apps/cms-admin/dist /app/apps/cms-admin/dist

# Local media and backups (CMS_MEDIA_DIR, CMS_BACKUP_DIR) live here when no bucket is configured.
RUN mkdir -p /app/data/media /app/data/backups && chown -R bun:bun /app
USER bun

EXPOSE 3100
HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=5 \
  CMD ["bun", "-e", "fetch('http://127.0.0.1:3100/health/ready').then((r) => process.exit(r.ok ? 0 : 1), () => process.exit(1))"]

# Migrations run at start under an advisory lock.
CMD ["bun", "src/index.ts"]
