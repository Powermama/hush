# hush CMS admin guidance

The editor for the blog, served by `apps/cms` on its own origin.

- Talk to the CMS only through the generated client (`src/api/cms.generated.ts`,
  `bun run api:client`); never edit it or `src/routeTree.gen.ts`. Sign-in
  (`src/api/session.ts`) is outside the OpenAPI document by design.
- UI primitives (`src/components/ui`, `src/shade-scope.tsx`, `src/providers`)
  are copied from Shade, Ghost Admin's design system (TryGhost/Ghost
  `apps/shade/src`, MIT), at the commit named in `packages/theme/README.md`.
  Before writing a component, copy Shade's: keep its code, add the attribution
  header and import Radix from the `radix-ui` package. Tokens and colors come
  from `@hush/theme`, never hard-coded values. Mount portals inside
  `ShadeScope` so overlays get the `.shade` styles.
- Rendered article HTML is shown only in the sandboxed preview frame
  (`src/components/article-preview.tsx`), styled by `@hush/article/article.css`.
- The CMS sends a strict Content Security Policy: no inline scripts, no
  third-party origins. Keep the admin within it.
- Required verification: `bun run lint`, `bun run api:check`, `bun run build`,
  and `bun run test:admin` in `apps/cms` (journeys in `docs/user-journeys/cms.md`).
