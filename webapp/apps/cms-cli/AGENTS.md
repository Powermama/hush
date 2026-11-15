# hush CMS CLI guidance

`hush-cms`, the command line for the blog CMS: what agents (the hush-seo
skill) and scripts use to draft, check, schedule and publish articles.

- Talk to the CMS only through the generated client (`src/api/cms.generated.ts`,
  `bun run api:client` from `apps/cms/openapi/hush-cms.json`); never edit it.
  A new operation starts in the CMS, then regenerates here.
- The CMS decides what is allowed (scopes, the owner's approval, the article
  contract); the CLI reports its answers and never re-implements a rule.
- Read article files only with `@hush/article/file`, never `@hush/article`
  itself: the binary must stay free of Node-only dependencies such as `sharp`.
- A pushed file is content only. Going live is always an explicit `schedule`
  or `publish`, which the CMS allows a token only for what the owner approved.
- Tokens never appear in arguments or output; they come from the Keychain or
  `HUSH_CMS_TOKEN`.
- Never import from `apps/cms`; the journeys start it as a separate process.

## Required verification

- `bun run lint`, `bun run api:check` and `bun run build`
- Journeys (CMS-CLI-001 to CMS-CLI-007 in `apps/cms/docs/user-journeys/cms.md`)
  against a real CMS: `HUSH_TEST_DATABASE_URL=postgresql://... bun test`
