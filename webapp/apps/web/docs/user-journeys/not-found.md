# Not-found page

Unknown addresses must not end in a raw JSON error for people.

NOTFOUND-001: a browser request (GET or HEAD accepting `text/html`) for an address no page or file matches receives the prerendered not-found page with status 404, `noindex, nofollow` and no caching. It shows the header, the sad hush mascot (3D when WebGL is available, the vector artwork otherwise), a short explanation, a link home, a link to the blog when that language has published articles, and the footer. Client-side navigation to an unknown route renders the same page.

NOTFOUND-002: addresses under `/de` get the German page (du form, like the landing page), linking home to `/de`.

NOTFOUND-003: API paths (`/v1`, `/health`, `/openapi.json`) and requests that do not accept HTML keep the JSON `not_found` error.

Tests: `tests/not-found.spec.ts`.
