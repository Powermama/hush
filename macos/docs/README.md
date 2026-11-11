# Native app documentation

[All hush docs](../../docs/README.md) · [Contribute](../../CONTRIBUTING.md)

| Task | Guide |
| --- | --- |
| Build and run | [Development](development.md) |
| Find expected behaviour and tests | [Shared journey index](../../docs/reference/user-journeys.md) |
| Investigate a freeze or stutter | [Responsiveness](operations/responsiveness.md) |
| Prepare a Developer ID release | [Notarization](operations/notarization.md) |
| Publish an update | [App updates](operations/app-updates.md) |
| Recreate the README screenshots | [Artwork notes](assets/README.md) |

`user-journeys/` owns observable behaviour and test mappings. `operations/` owns
repeatable engineering tasks. `research/` contains dated investigations and
benchmark evidence, including their limitations. `PRD-*` files are planning
history and may describe superseded proposals.

When changing a feature, update its journey and relevant evidence rather than
adding a second conflicting specification. Preserve case-sensitive filenames
and identifiers even though the product name is written **hush**.
