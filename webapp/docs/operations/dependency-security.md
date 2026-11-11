# Dependency security review

Reviewed 11 November 2026 against the web application and proof service. This is
an advisory triage and dependency update, not a complete penetration test or a
claim that the application has no vulnerabilities.

## What changed

The initial GitHub snapshot contained 52 open advisories: 43 for Hono, six for
Vite and one each for Zod, Drizzle ORM and jsdiff. Eight were high, 39 moderate
and five low. These are dependency matches, not evidence of 52 successful attacks.

| Dependency | Previous | Updated | Reason |
| --- | --- | --- | --- |
| Hono | 4.9.6 | 4.13.18 | Includes the original advisories and the newer static-path decoding fix. |
| Vite | 8.2.0 | 8.2.4 | Patched development middleware and editor integration. |
| Zod | 4.1.5 | 4.6.6 | Constrained collection validation resource limits. |
| Drizzle ORM | 0.44.5 | 0.45.2 | Escaping of SQL identifiers. |
| jsdiff | 8.0.2 | 8.0.3 | Patch parser/application resource handling. |
| AWS S3 client and presigner | 3.883.0 | 3.1167.0 | Updated XML parser and UUID dependency. |
| TanStack React Router | 1.170.18 | 1.170.46 | Patched Seroval serialization dependency. |
| concurrently | 10.0.4 | 10.0.7 | Patched shell quoting dependency. |
| drizzle-kit | 0.31.4 | 0.31.11 | Updated development build tooling. |
| Tailwind and its Vite plugin | 4.3.3 | 4.3.5 | Patched source-map parsing dependency. |

The lockfile audit found additional transitive advisories beyond GitHub's
initial manifest-level list. The final `bun audit` returned no known
vulnerabilities. Advisory databases change. The existing web CI job runs `bun audit` after its frozen install and blocks merging on reported advisories; no extra macOS runner is added.

## Reachability and evidence

- Hono JWT/JWK, Basic/Bearer Auth, JSX rendering, cookies, cache middleware,
  IP restrictions, SSE, `parseBody`, `app.mount`, `toSSG`, proxy helpers and
  Lambda/Workers adapters are not used by this application. Proof signatures
  use the application's P-256 verification. These conditions were checked in
  source; this does not justify retaining the vulnerable package.
- CORS uses an explicit allowed origin and header list without credential
  reflection. Static serving exposes the public `dist` directory, not protected
  proof storage. Production runs Bun on Linux, not the Vite development server
  or the Windows static adapter. See the upstream
  [static-path advisory](https://github.com/honojs/hono/security/advisories/GHSA-5r4p-p66f-jhc7).
- The upload route does use Hono's body limit. A bounded loopback HTTP regression
  sends 8,000,001 bytes with Content-Length and chunked framing. Updated code
  returns `413` with `body_too_large` and stores no object. Each request uses a
  separate connection because early rejection can leave an undrained body.
  This tests the intended rejection, not a demonstrated unauthorized upload.
- Drizzle queries use fixed schema identifiers and parameterized values. No
  user-controlled `sql.identifier()` or aliases were found. The
  [upstream identifier advisory](https://github.com/drizzle-team/drizzle-orm/security/advisories/GHSA-gpj5-g38j-94v9)
  explains that condition. Schema generation was smoke-tested to a temporary
  output directory; no database migration was applied.
- jsdiff is used for word/character comparison, not `parsePatch` or `applyPatch`.
  Zod parses untrusted API and decrypted proof data, so its update remains
  important even without attempting a resource-exhaustion attack.
- S3-compatible storage is tested with dummy credentials and a loopback fixture:
  presigned URL shape, exact encrypted bytes, deletion and XML missing-object
  responses. This is compatibility coverage, not a live Cloudflare R2 test.

## Temporary development overrides

`package.json` pins two transitive overrides while upstream parents retain old
ranges. Both are development dependencies, not the deployed proof-service API:

- `basic-ftp` 6.2.6 replaces the vulnerable version beneath Lighthouse CI's
  proxy resolver. Its CommonJS `Client` methods used by `get-uri` remain present;
  resolver loading and a local data-URI read are smoke-tested. No FTP server is
  contacted.
- `esbuild` 0.25.12 replaces the legacy copy beneath drizzle-kit's ESM loader
  and is used consistently by development tooling. Build, Vite browser
  journeys and schema generation validate the paths used by hush. This does
  not test an exposed esbuild development server; hush does not run one.

Remove each override when its parent resolves a patched version without it.
Do not add runtime dependencies merely to control a transitive version.

## Repeatable checks

Run `bun install --frozen-lockfile`, `bun audit`, `bun run lint`,
`bun test server`, `bun run api:check`, `bun run build`, and
`bunx playwright test` from `webapp/`. The upload and storage regression tests
are in `server/app.test.ts` and `server/storage/s3-object-store.test.ts`.

After merging, confirm GitHub re-evaluates its alerts and Coolify deploys the
updated lockfile. Do not dismiss alerts to make the count appear clean.
