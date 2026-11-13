# Search and link previews

## Architecture

`shared/site.ts` is the public page catalogue: canonical paths, titles,
descriptions, languages and indexing eligibility. `shared/site-head.ts` generates
Open Graph, X cards, canonical/hreflang links and the homepage's SoftwareApplication
structured data. Do not invent ratings, testimonials or keyword statistics.

The existing TanStack Router renders each catalogue page at build time through
its documented SSR handler. Vite compiles the server entry and client assets.
The client uses TanStack's RouterClient to hydrate the same component tree.
There are no per-visitor SSR computations, crawler-specific content or new
runtime dependencies. Browser-only preferences are applied after hydration.

Build output is separated deliberately:

- `dist/`: public assets and a generic noindex client shell for proof recipients.
- `dist-pages/pages.json`: prerendered public documents served only through the
  explicit Hono route catalogue, with each page's indexing/cache policy.
- `dist-ssr/`: build-time renderer, excluded from the production container.

The router's bootstrap is emitted as a hashed external script to preserve
`script-src 'self'`. No unsafe-inline exception is introduced. Private proofs,
fragment keys and message text never enter prerendering or discovery files.
Unknown pages remain HTTP 404; private alpha releases and unfinished legal
pages retain noindex/no-store. `/releases/latest` redirects to the current version.

## Blog

Published articles enter the same catalogue through
`shared/blog-posts.generated.ts`, generated at build time from the hush CMS in
production (from `content/blog/<lang>/` or test fixtures otherwise), so
canonical URLs, the sitemap
(`lastmod` from each article's `updated` date), `llms.txt` and prerendering work
as for every other page. Articles get `og:type article` and `BlogPosting`
structured data; FAQPage and HowTo markup are not used because Google no longer
shows those rich results. `keyword` fields are internal and never rendered.
Each language has an Atom feed at `/blog/feed.xml` or `/de/blog/feed.xml`. See
[the blog journeys](user-journeys/blog.md) and `content/blog/README.md`.

## Commands and generated files

```sh
bun run build
bun run lint
bun test server
bun run api:check
bunx playwright test
bun run test:seo
```

`bun run site:generate` generates `public/sitemap.xml` and `public/llms.txt` from
the public catalogue during every build. They list the blog, so like the blog
output they are not committed. Edit their generator. Sitemap
lastmod dates describe real content updates, not arbitrary build times.

`bun run test:seo` uses the pinned GoogleChrome Lighthouse CI package and
`lighthouserc.cjs` to assert all applicable SEO audits on the two public pages.
It starts an isolated test service on port 4315 and uses Playwright's installed
Chromium (or `CHROME_PATH`). Install Chromium with `bunx playwright install chromium`
and use Node 22.19+ for Lighthouse CI. Reports stay in the ignored `.lighthouseci/`
directory; nothing is uploaded. This optional local command adds no scheduled
GitHub runner usage. It is a technical regression check, not a ranking score or
a substitute for the no-JavaScript Playwright journeys and Search Console.

`bun run site:social` renders `scripts/social-card.html` into the two 1200 x 630
PNG files in `public/social/` using the existing Playwright dependency. Render
and inspect both when changing the artwork; commit the outputs. The homepage
composition pairs the listening HUD with an example message. Verified Messages
has a separate signed-history mock-up. Both are product illustrations, not
screenshots or real user records. No network
requests, generated AI images, private messages or fabricated usage statistics
are used. The Docker build uses those committed PNGs and needs no browser.

Use `bun run dev:web` for the usual Vite HMR preview. To verify the actual
prerendered HTML and HTTP policy, run `bun run build` then `bun run serve:e2e`.

## Production follow-through

1. Deploy the reviewed commit. Check initial HTML, headers, image URLs,
   `/sitemap.xml` and `/llms.txt` through the public domain and Cloudflare.
2. Verify a domain property in Google Search Console through the owner's DNS
   account, submit the sitemap, then inspect the two public page URLs. DNS
   verification does not require installing visitor analytics. Do not guess or
   commit verification tokens. Check Cloudflare crawler blocks if inspection fails.
3. Validate public structured data and previews with Google's Rich Results Test,
   Meta's Sharing Debugger and LinkedIn's Post Inspector. Card caches can outlive
   deployment; request a recrawl after changing them. Social platforms choose
   their own layout. Metadata is not a guarantee of a particular card or ranking.
4. Watch Search Console impressions, indexed pages, queries, click-through rate
   and Core Web Vitals. Add useful public guides around genuine user questions
   such as offline dictation, supported languages and Mac setup. Keep the visual
   landing page concise; do not add hidden keyword text or cloned city pages.
5. Maintain accurate links from the public repository and relevant community
   discussions. No purchased links, fabricated reviews or automatic spam outreach.

`llms.txt` is an optional community proposal. Google says no special AI text
file is required for its AI search features. It does not replace ordinary HTML,
robots directives or a sitemap, and cannot guarantee inclusion in model answers.
Orval is separate API-client tooling; the two small proof fetch functions do
not currently justify a new generator. Existing OpenAPI drift checks remain.

## Primary references

- [Google: JavaScript SEO](https://developers.google.com/search/docs/crawling-indexing/javascript/javascript-seo-basics)
- [Google: AI search features](https://developers.google.com/search/docs/appearance/ai-features)
- [Google: SEO starter guide](https://developers.google.com/search/docs/fundamentals/seo-starter-guide)
- [Vite: SSR and prerendering](https://vite.dev/guide/ssr)
- [TanStack Router: SSR](https://tanstack.com/router/latest/docs/framework/react/guide/ssr)
- [Open Graph protocol](https://ogp.me/)
- [GoogleChrome Lighthouse CI configuration](https://github.com/GoogleChrome/lighthouse-ci/blob/main/docs/configuration.md)
- [Lighthouse SEO audit scope](https://developer.chrome.com/docs/lighthouse/seo/meta-description)
- [llms.txt proposal](https://llmstxt.org/)

The pre-change external audit reproduced empty HTML content and the homepage's
canonical/title on `/verified-messages`. Its high aggregate score was not treated
as success: the observed crawl output, HTTP tests and real browser behaviour are
the relevant evidence.
