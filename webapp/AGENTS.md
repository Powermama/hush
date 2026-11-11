# hush web agent guidance

Read `docs/user-journeys/proof-recipient.md` before changing proof APIs, cryptography, storage, or the recipient page. Preserve its journey IDs and fail-closed invariants in code and tests.

## Required verification

- Type checking: `bun run lint`
- Backend unit and integration tests: `bun test server`
- OpenAPI drift check: `bun run api:check`
- Browser journeys: `bunx playwright test`

Playwright tests must assert user-observable outcomes on desktop and mobile. Keep cryptographic protocol tests deterministic. Compare RFC 3339 timestamps by exact instant and reject any precision loss that changes that instant.

When changing a user-visible journey, update its journey document and test mapping in the same change.
