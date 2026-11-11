# Private proof short links

Hush short links are first-party aliases for completed encrypted proofs. They are not a general URL shortener.

## Production shape

Set `HUSH_SHORT_BASE_URL` to the public short domain with a trailing slash:

```text
HUSH_SHORT_BASE_URL=https://behu.sh/
```

The Hono service resolves `/<code>` directly and returns a `302` to the canonical verifier URL configured by `HUSH_PUBLIC_BASE_URL`. `/s/<code>` remains available as a compatibility route. A same-domain Coolify deployment does not require a separate edge rewrite.

If a dedicated short-link edge is introduced later, it may internally rewrite `/<code>` to `/s/<code>` without redirecting.

The redirect `Location` must not contain a fragment. Standards-compliant browsers inherit the original `#k=` fragment, so neither the edge nor Hono receives the private decryption key.

## Security contract

- Accept only `GET` and `HEAD` for an alias.
- Resolve only exactly 6 Base64URL characters.
- Never accept a caller-provided destination.
- Never log full browser URLs in client telemetry.
- Preserve `Referrer-Policy: no-referrer` and `X-Robots-Tag: noindex, nofollow`.
- Apply the application rate limit to both alias routes. If an edge is added, rate limit there as defense in depth.
- Keep PostgreSQL as the source of truth. Edge caching may cache successful redirects for at most five minutes.
- Map expired and revoked aliases to the canonical verifier so recipients receive the signed proof status. Return `404` for unknown aliases.

## Availability

The alias row is created idempotently after proof completion. A unique code index and unique proof index ensure one immutable alias per proof. Collision retries occur before a short URL is returned. If alias allocation is unavailable, publication fails closed and Hush does not claim that a verified link was added.

Six Base64URL characters provide a 36-bit public locator space. The code is not an authorization secret: proof contents remain encrypted and require the independent fragment key. Rate limits reduce enumeration, while the database uniqueness constraint and allocation retries resolve collisions without overwriting an existing alias.

Local development defaults to `<HUSH_PUBLIC_BASE_URL>/s/`. Production may use a root short base such as `https://behu.sh/` without a separate edge.
