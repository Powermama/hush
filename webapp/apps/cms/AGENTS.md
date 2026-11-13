# hush CMS guidance

The blog CMS: posts, revisions, scheduling and the admin API for the owner and
for agents. It runs as its own service with its own PostgreSQL, apart from
Verified Messages.

## Required verification

- Type checking: `bun run lint`
- Journeys against PostgreSQL: `HUSH_TEST_DATABASE_URL=postgresql://... bun test`
  (each test file creates and drops its own database; CI refuses to skip them)
- OpenAPI drift check: `bun run api:check`

## Rules

- Never import from `apps/web` or read `DATABASE_URL` or
  `HUSH_SERVICE_PRIVATE_JWK`; `tests/boundary.test.ts` enforces it.
- Article rules come from `@hush/article`. Do not re-implement them here.
- Keep the schema in third normal form. Change it with `bun run db:generate`;
  migrations stay additive so the previous release keeps running during deploys.
- Every state change runs in one transaction with its revision.
- When a journey changes, update `docs/user-journeys/cms.md` and its test.
