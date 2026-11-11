# Website and proof-service documentation

[All hush docs](../../docs/README.md) · [Run locally](../README.md) ·
[Contribute](../../CONTRIBUTING.md)

| Task | Guide |
| --- | --- |
| Find behaviour and browser tests | [Shared journey index](../../docs/reference/user-journeys.md) |
| Understand proof verification | [Recipient contract](user-journeys/proof-recipient.md) |
| Maintain search and social previews | [Search discovery](search-discovery.md) |
| Deploy or move the service | [Coolify deployment](operations/coolify-deployment.md) |
| Understand private short links | [Short-link operation](operations/proof-short-links.md) |
| Inspect the API | [OpenAPI contract](../openapi/hush-provenance.json) |
| Check image attribution | [Artwork credits](../public/art/CREDITS.md) |

`user-journeys/` owns observable behaviour and test mappings. `operations/`
contains deployment and service guides. `design/` records visual direction and
the reasons behind it; a design proposal is not evidence that a feature shipped.
Generated contracts are updated through their generator, never edited by hand.

Public image caching and CDN verification: [asset delivery](operations/asset-delivery.md).
