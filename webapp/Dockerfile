FROM oven/bun:1.3.9-alpine AS dependencies

WORKDIR /app
COPY package.json bun.lock ./
RUN bun install --frozen-lockfile

FROM dependencies AS build

COPY index.html vite.config.ts tsconfig*.json ./
COPY public ./public
COPY server ./server
COPY shared ./shared
COPY src ./src
COPY scripts/generate-site-files.ts ./scripts/generate-site-files.ts
RUN bun run build

FROM oven/bun:1.3.9-alpine AS runtime

WORKDIR /app
ENV NODE_ENV=production \
    PORT=3000 \
    HUSH_DATA_DIR=/app/data

COPY package.json bun.lock ./
RUN bun install --frozen-lockfile --production
COPY --from=build /app/dist ./dist
COPY server ./server
COPY shared ./shared
COPY scripts/healthcheck.ts ./scripts/healthcheck.ts

RUN mkdir -p /app/data && chown -R bun:bun /app
USER bun

EXPOSE 3000
HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=5 \
  CMD ["bun", "scripts/healthcheck.ts"]

CMD ["sh", "-c", "if [ -n \"${DATABASE_URL:-}\" ]; then bun run db:migrate; fi; exec bun server/index.ts"]
