# Public discovery journey

A search crawler or social preview fetcher can read public hush pages without
running JavaScript. Human visitors hydrate the same content and retain the
existing entrance, WebGL, reduced-motion and mobile-download experiences.

## Invariants

- The catalogue owns canonical URLs, titles, descriptions and indexing policy.
- Initial HTML contains the actual page heading, copy and navigable links.
- Each public URL supplies its own Open Graph and X preview with a public image.
- Only actual language equivalents receive reciprocal hreflang links.
- Structured data reflects visible product facts, without invented reviews.
- Private proofs are client-only, noindex and no-store. Neither their contents
  nor their fragment keys enter HTML generation, sitemaps, llms.txt or previews.
- Legal drafts and private release pages remain noindex/no-store even though
  their publicly accessible documents are prerendered for readability.
- Unknown URLs return 404. Server HTML is not replaced with a crawler-only page.
- The Content Security Policy is preserved, including script-src 'self'.

## Evidence

`tests/search-discovery.spec.ts` covers these scenarios on Chromium, mobile and
WebKit:

- SEARCH-001: JavaScript-disabled visitors can read each public heading, find
  navigation, obtain distinct metadata, and fetch both 1200 x 630 preview images.
- SEARCH-002: React hydrates pages without CSP errors, lost content or hydration
  mismatches. Existing entrance/mobile/proof journeys verify interactive behaviour.
- SEARCH-003: Discovery files contain only indexable public destinations;
  private responses retain their headers; unknown URLs return 404.

Update the catalogue and this contract when adding a public page. See
`../search-discovery.md` for generation, deployment and ongoing search measurement.
