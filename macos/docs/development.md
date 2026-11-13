# Developing hush

## Toolchain

Use an Apple silicon Mac with Xcode and its command-line tools selected. The app
targets macOS 15+. Current development uses Xcode 26.6; the pinned MLX package
requires Swift 6.3. Apple Intelligence features also depend on their system
availability. Downloaded Qwen models provide a separate local writing option.

The repository includes a bundled Whisper base model for initial dictation.
Additional speech, language, and voice models are downloaded through the app.

## Run locally

Run these commands from `macos/` in the monorepo:

```sh
open Hush/Hush.xcodeproj
```

Select the **Hush** scheme. Under **Signing & Capabilities**, select your own team
for the targets you build. Review the pinned package plugins and macros before
trusting them in Xcode. Run with **⌘R**.

The command-line equivalent, after that setup, is:

```sh
xcodebuild -project Hush/Hush.xcodeproj -scheme Hush -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -onlyUsePackageVersionsFromResolvedFile build
```

The first build resolves the checked-in package versions and can take several
minutes. Keep package trust decisions local to the reviewed dependencies; don't
disable validation globally.

## Local proof service

Ordinary dictation and local AI do not need the proof service. Debug builds point
Verified Messages at `http://127.0.0.1:3000`; Release uses `https://behu.sh`.
The service lives in [`webapp/`](../../webapp/apps/web/README.md) in this monorepo.
Start it with `bun run dev` from that directory.

For a development launch, endpoints can be overridden through the Xcode scheme
or environment:

```sh
HUSH_PROOF_SERVICE_URL=http://127.0.0.1:4000 \
HUSH_PROOF_SHORT_URL=http://127.0.0.1:4000/s/ \
  /path/to/hush.app/Contents/MacOS/hush
```

Remote endpoints must use HTTPS. HTTP is accepted only for loopback addresses.

## Verify a change

Run the package tests:

```sh
swift test --package-path Packages/HushProvenance
```

With the sibling web service running on port 3000, run the integration journey:

```sh
HUSH_PROVENANCE_E2E_BASE_URL=http://127.0.0.1:3000 \
  swift test --package-path Packages/HushProvenance \
  --filter enrollsAndPublishesWithHonoService
```

Build the Release configuration:

```sh
xcodebuild -project Hush/Hush.xcodeproj -scheme Hush -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -onlyUsePackageVersionsFromResolvedFile build
```

For native unit tests, UI journeys, sanitizers, and Instruments, follow
[responsiveness checks](operations/responsiveness.md). Read each relevant
[journey contract](user-journeys) for its test mapping. Model evaluations are
separate opt-in work; don't treat a fixture pass as evidence that live desktop
operation works.

## Project map

| Location | Purpose |
| --- | --- |
| `Hush/Hush` | Native app, audio, hotkeys, control centre, assistant, and insertion |
| `Hush/HushTests`, `Hush/HushUITests` | Domain and native UI tests |
| `Hush/BundledModels` | Bundled offline speech model |
| `Packages/HushProvenance` | Signed-message domain logic and typed service client |
| `docs/user-journeys` | Observable behaviour and test ownership |
| `docs/operations` | Distribution and runtime diagnostics |
| `scripts` | Packaging, release checks, and development tooling |

## Releases

hush is in alpha. The numeric bundle version and increasing build number are
separate from prerelease tags such as `v0.1.0-alpha.5`. Release assets must match
the committed source revision. Beta requires the core journeys to be
feature-complete without known critical issues; 1.0 also requires a stable data
model, regression coverage, and a tested update path.

Use `./scripts/build-dmg.sh` for a Developer ID candidate and
`./scripts/build-local-dmg.sh` for local service testing. The distribution script
stops at local checks by default; notarization requires explicit opt-in. Follow
[the notarization guide](operations/notarization.md) and
[update publishing](operations/app-updates.md) for the complete process.

Published alpha builds update through Sparkle using independently signed update
archives at `https://updates.behu.sh`. A development build is not a public release.
