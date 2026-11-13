# syntax=docker/dockerfile:1
# Built from the workspace root: docker build --file apps/web/Dockerfile .
FROM oven/bun:1.3.9-alpine AS dependencies

WORKDIR /app
# A frozen install checks the lockfile against every workspace, so copy each
# workspace manifest (COPY --parents keeps their paths). Installs stay cached
# until a manifest changes.
COPY --parents package.json bun.lock apps/*/package.json packages/*/package.json ./
RUN bun install --frozen-lockfile --filter @hush/web
COPY packages/article ./packages/article

FROM dependencies AS build

WORKDIR /app/apps/web
COPY apps/web/index.html apps/web/vite.config.ts apps/web/tsconfig*.json ./
COPY apps/web/messages ./messages
COPY apps/web/project.inlang ./project.inlang
COPY apps/web/public ./public
COPY apps/web/server ./server
COPY apps/web/shared ./shared
COPY apps/web/src ./src
COPY apps/web/scripts/generate-site-files.ts apps/web/scripts/prerender.ts ./scripts/
COPY apps/web/scripts/prerender ./scripts/prerender
RUN bun run build

FROM oven/bun:1.3.9-alpine AS runtime

WORKDIR /app
ENV NODE_ENV=production \
    PORT=3000 \
    HUSH_DATA_DIR=/app/data

# Every workspace manifest, as in the dependencies stage.
COPY --parents package.json bun.lock apps/*/package.json packages/*/package.json ./
RUN bun install --frozen-lockfile --production --filter @hush/web
COPY packages/article ./packages/article
WORKDIR /app/apps/web
COPY --from=build /app/apps/web/dist ./dist
COPY --from=build /app/apps/web/dist-pages ./dist-pages
COPY apps/web/server ./server
COPY apps/web/shared ./shared
COPY apps/web/scripts/healthcheck.ts ./scripts/healthcheck.ts

RUN mkdir -p /app/data && chown -R bun:bun /app
USER bun

EXPOSE 3000
HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=5 \
  CMD ["bun", "scripts/healthcheck.ts"]

CMD ["sh", "-c", "if [ -n \"${DATABASE_URL:-}\" ]; then bun run db:migrate; fi; exec bun server/index.ts"]
