# hush CMS admin guidance

The editor for the blog, served by `apps/cms` on its own origin.

- Talk to the CMS only through the generated client (`src/api/cms.generated.ts`,
  `bun run api:client`); never edit it or `src/routeTree.gen.ts`. Sign-in
  (`src/api/session.ts`) is outside the OpenAPI document by design.
- Add UI from shadcn (`bunx --bun shadcn@latest add <component>`) before writing
  components; colors come from `src/theme/shade.css`, not hard-coded values.
- Rendered article HTML is shown only in the sandboxed preview frame
  (`src/components/article-preview.tsx`), styled by `@hush/article/article.css`.
- The CMS sends a strict Content Security Policy: no inline scripts, no
  third-party origins. Keep the admin within it.
- Required verification: `bun run lint`, `bun run api:check`, `bun run build`,
  and `bun run test:admin` in `apps/cms` (journeys in `docs/user-journeys/cms.md`).
