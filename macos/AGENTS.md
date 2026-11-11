# hush macOS agent guidance

Read `docs/user-journeys/verified-messages.md` before changing Verified Messages, transcription insertion, or the HUD. Preserve its journey IDs and trust invariants in code and tests.

## Required verification

- Package unit tests: `swift test --package-path Packages/HushProvenance`
- Swift-to-Hono integration: start the sibling `webapp` server, then run `HUSH_PROVENANCE_E2E_BASE_URL=http://127.0.0.1:3000 swift test --package-path Packages/HushProvenance --filter enrollsAndPublishesWithHonoService`
- Full app build: `xcodebuild -project Hush/Hush.xcodeproj -scheme Hush -configuration Release build`

Use Swift Testing for domain and integration tests. Use XCTest UI automation for complete macOS user journeys. Never commit Swift OpenAPI generated sources from build directories.

When changing a user-visible journey, update its journey document and test mapping in the same change.
