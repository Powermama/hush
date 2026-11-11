# Private alpha download journey

This document defines the public download and first-launch experience for hush testers.

## Goal

Visitors see only builds that are ready for distribution. Earlier unnotarized builds and their Terminal workaround have been withdrawn. The current download is alpha.5, build 14, which restores the Finder installer layout. Alpha.4 remains in the release history as the first notarized alpha. The notes identify the full public release and open sourcing as future intentions, not current availability.

## State flow

```text
Download selected
  -> release metadata selects the immutable notarized build
  -> browser downloads that exact DMG and opens its release notes
  -> tester moves hush to Applications and opens it normally
```

## Trust invariants

- An empty release catalog is a supported state. Download actions lead to the availability page.
- Removed and unknown release URLs return HTTP 404 with no indexing and no caching.
- Never present Terminal commands to remove quarantine or bypass Gatekeeper.
- Removing old instructions does not imply that an old build was notarized.
- Add new release metadata only after Apple accepts the distributed artifact, its ticket is stapled, installation is checked, and the immutable public download is verified.
- The public download URL must return a DMG, never an HTML error page.
- Publish immutable update archives before the appcast and publish the stable DMG alias last.
- Download buttons must point to the exact immutable DMG and must not add cache-busting query strings.
- The immutable DMG must use `Content-Disposition: attachment` and one-year immutable caching.
- Serve the mutable appcast and stable DMG alias with `Cache-Control: no-store` and a Cloudflare cache bypass rule.
- Future updates must be accepted only after Sparkle verifies their EdDSA signature.
- No Cloudflare R2 credential may be embedded in the web app, Coolify configuration, or macOS app.

## Scenarios

### DOWNLOAD-001 - Show current download availability

Selecting a download action starts the exact alpha.5 build 14 DMG and opens its matching release notes. The shared header offers the same current download on release pages; their article content contains no redundant or older download. The release index retains the alpha.4 milestone. If the catalog is empty in the future, download actions lead to the availability page.

### DOWNLOAD-002 - Retire the old installation workaround

Given a visitor opens a removed release URL, the website returns 404 and offers a way back to the release index. Neither the current release index nor removed release pages offer a Terminal command, a copy-command action, or a download of an older build.

### DOWNLOAD-003 - Serve a complete release channel

Given a release has been published, the stable DMG URL, signed archive, and appcast resolve publicly. The appcast enclosure references the exact signed archive uploaded to R2. Removing website listings does not delete objects used by existing installations.

## Test mapping

| Journey | Automated evidence |
| --- | --- |
| DOWNLOAD-001 | `tests/landing.spec.ts` checks the immutable alpha.5 download, download event in Chromium, matching release popup in all browsers, retained alpha.4 milestone, and the future open-source intention on desktop, mobile, and WebKit. |
| DOWNLOAD-002 | `tests/landing.spec.ts` verifies removed release URLs return 404, retain no-index/no-store headers, contain no bypass command or download link, and allow returning to the release index. |
| DOWNLOAD-003 | `macos/scripts/verify-update-feed.sh` checks public feed metadata and archive availability. The release's public-download verification report records byte equality, Gatekeeper, layout and Sparkle EdDSA signature checks. `macos/Hush/HushUITests/AppUpdateJourneyTests.swift` verifies the in-app update entry point. |

## Change rule

Reproduce download failures against the public `updates.behu.sh` URLs first. Fix the narrow publish or routing fault, then verify the R2 objects, appcast signature, website journey, and in-app update entry point before announcing a release.
