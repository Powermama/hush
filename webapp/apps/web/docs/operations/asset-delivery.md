# Public asset delivery

Artwork and app icons are imported through Vite from `src/media/`. Vite gives
them content-hashed URLs in `/assets/` in the client build, CSS and prerendered
HTML. A changed file receives a new URL; unchanged files can stay cached across
deployments. Do not place these images back in `public/` or add timestamp query
strings that defeat reuse.

The server sends `public, max-age=31536000, immutable` for build assets. Public
HTML uses `no-cache, must-revalidate`, so browsers check for current page content.
Stable public files such as robots.txt, attribution and social images retain
short caching. Private proofs and APIs must never be included in a broad
Cloudflare "cache everything" rule.

Cloudflare returned `CF-Cache-Status: HIT` for public images and lighting on
11 November 2026. This means edge caching is active, not that every request from
every location is already warm. The HTML response was `DYNAMIC`, as expected.
No new Cloudflare plan or image service is required for hashed-asset caching.

Responsive WebP sources, intrinsic dimensions, below-the-fold lazy loading and
same-origin attribution remain intact. Image bytes and visual treatments are
unchanged. `tests/public-assets.spec.ts` verifies matching prerender/hydration
URLs, cache headers, successful image decoding and responsive source delivery.

After deployment, inspect a versioned image twice with `curl -I`. Expect an
immutable cache header and eventually `CF-Cache-Status: HIT`; a cold edge may
first return `MISS`. Check the actual browser response too, since Cloudflare
cache rules can override origin headers. Do not flush all caches on each deploy.

References: [Vite static assets](https://vite.dev/guide/assets),
[Cloudflare cache responses](https://developers.cloudflare.com/cache/concepts/cache-responses/).
