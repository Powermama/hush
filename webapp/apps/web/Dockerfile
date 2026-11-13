# syntax=docker/dockerfile:1
# Built from the workspace root: docker build --file apps/web/Dockerfile .
#
# Two final targets share every stage but the blog's source:
#   runtime      (default) the blog from content/blog in the repository
#   runtime-cms  production: the blog from the hush CMS, read during the build
# The build stages run on Debian so Chromium can render blog covers; the
# runtime image stays Alpine.
FROM oven/bun:1.3.9 AS dependencies

WORKDIR /app
# A frozen install checks the lockfile against every workspace, so copy each
# workspace manifest (COPY --parents keeps their paths). Installs stay cached
# until a manifest changes.
COPY --parents package.json bun.lock apps/*/package.json packages/*/package.json ./
RUN bun install --frozen-lockfile --filter @hush/web
COPY packages/article ./packages/article

FROM dependencies AS source

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
COPY apps/web/scripts/blog ./scripts/blog

FROM source AS build
RUN bun run build

FROM source AS build-cms
# Covers are rendered with Chromium; only missing ones, as in development.
RUN bunx playwright install --with-deps chromium
# Coolify builds with the host network, so the CMS answers on the server's
# loopback. ADD re-fetches this URL on every build and keeps the next step's
# cache only while the site revision is unchanged.
ARG HUSH_CMS_URL=http://127.0.0.1:3100
ADD ${HUSH_CMS_URL}/v1/site/revision /tmp/cms-revision
# The read-only token arrives as a build secret and never enters a layer.
RUN --mount=type=secret,id=HUSH_CMS_TOKEN,env=HUSH_CMS_TOKEN,required=true \
    HUSH_CMS_URL="$HUSH_CMS_URL" bun scripts/blog/pull-cms.ts /tmp/cms-content \
    && HUSH_BLOG_CONTENT_DIR=/tmp/cms-content bun run blog:generate \
    && bun run build

FROM oven/bun:1.3.9-alpine AS runtime-base

WORKDIR /app
ENV NODE_ENV=production \
    PORT=3000 \
    HUSH_DATA_DIR=/app/data

# Every workspace manifest, as in the dependencies stage.
COPY --parents package.json bun.lock apps/*/package.json packages/*/package.json ./
RUN bun install --frozen-lockfile --production --filter @hush/web
COPY packages/article ./packages/article
WORKDIR /app/apps/web
COPY apps/web/server ./server
COPY apps/web/shared ./shared
COPY apps/web/scripts/healthcheck.ts ./scripts/healthcheck.ts
RUN mkdir -p /app/data && chown -R bun:bun /app

EXPOSE 3000
HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=5 \
  CMD ["bun", "scripts/healthcheck.ts"]
CMD ["sh", "-c", "if [ -n \"${DATABASE_URL:-}\" ]; then bun run db:migrate; fi; exec bun server/index.ts"]

FROM runtime-base AS runtime-cms
COPY --from=build-cms /app/apps/web/dist ./dist
COPY --from=build-cms /app/apps/web/dist-pages ./dist-pages
COPY --from=build-cms /app/apps/web/shared/blog-posts.generated.ts ./shared/blog-posts.generated.ts
USER bun

FROM runtime-base AS runtime
COPY --from=build /app/apps/web/dist ./dist
COPY --from=build /app/apps/web/dist-pages ./dist-pages
USER bun
