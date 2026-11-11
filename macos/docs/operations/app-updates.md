# hush app updates with Sparkle and Cloudflare R2

Hush uses one direct-distribution pipeline from private alpha testing through
notarized production releases:

The supported hardware is Apple Silicon (arm64), on macOS 15 or later. Intel
Macs are not supported by Hush's local AI stack. The transcription target is an
8 GB Mac. For Hush Assistant, recommend 16 GB unified memory without imposing a
16 GB minimum or preventing setup on 8 GB. Actual 8 GB performance still needs
hardware validation; do not present the target as a completed benchmark.

Sparkle 2.9+ generates an `arm64` hardware requirement from the app executable.
The packaging script verifies that metadata before publishing. Any upgrade
path from an older Sparkle client needs separate compatibility review.

```text
Xcode Release archive
  -> Developer ID export
  -> local preflight and review (default stopping point)
  -> explicitly requested Apple notarization and stapling
  -> Sparkle EdDSA-signed ZIP and appcast
  -> Cloudflare R2
  -> https://updates.behu.sh
```

The bundle identifier, Sparkle public key, and update origin stay stable.
Public packaging and publishing require successful postflight checks. See
[Developer ID distribution](notarization.md) for the strategy and source review.

## Cloudflare setup

### 1. Create the bucket

1. Open **Cloudflare Dashboard > Storage & databases > R2**.
2. Create the dedicated public update bucket. The current production bucket is
   named `hush`.
3. Open the bucket, then **Settings > Public access > Custom Domains**.
4. Select **Connect Domain** and enter `updates.behu.sh`.
5. Confirm the connection. Cloudflare creates the required DNS record and
   serves the bucket through its CDN.

Do not point `updates.behu.sh` at Coolify. `behu.sh` continues to point at the
Coolify web service, while `updates.behu.sh` points directly at R2.

After the first publish, these URLs become public:

```text
https://updates.behu.sh/alpha/appcast.xml
https://updates.behu.sh/alpha/hush-<version>-<channel>-build.<build>.zip
https://updates.behu.sh/downloads/hush-latest.dmg
```

### 2. Create a publishing token

1. In R2, select **Manage R2 API Tokens**.
2. Create a token with **Object Read & Write**.
3. Scope it only to the `hush` update bucket.
4. Save its Access Key ID, Secret Access Key, and S3 endpoint in a password
   manager. The secret is shown only once.

Never put these values in Git, the app bundle, R2, or Coolify. They are build
machine or CI secrets only. The running proof service does not need access to
the update bucket.

Cloudflare's custom domain makes the complete bucket public. Do not connect
`updates.behu.sh` to a bucket used for encrypted proof objects or any other
application data. Keep the `hush` bucket dedicated to public release artifacts
even when other application objects are encrypted.

## Build-machine setup

Install the AWS CLI once:

```sh
brew install awscli
```

Create the ignored local release environment once:

```sh
cp .env.update.example .env.update.local
chmod 600 .env.update.local
```

Fill `.env.update.local` with the S3 endpoint and the scoped R2 API-token
credentials. `publish-update-r2.sh` loads this file automatically. CI can use
secret environment variables without creating this file. Select a different
file with `HUSH_UPDATE_ENV_FILE`, or set it to a nonexistent path when every
value comes from the CI environment.

The endpoint contains the Cloudflare account ID only. Do not append the bucket
name:

```dotenv
HUSH_R2_ENDPOINT=https://ACCOUNT_ID.r2.cloudflarestorage.com
HUSH_R2_BUCKET=hush
AWS_ACCESS_KEY_ID=YOUR_R2_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY=YOUR_R2_SECRET_ACCESS_KEY
AWS_DEFAULT_REGION=auto
```

The AWS CLI is used deliberately because R2 implements the standard S3 API and
the release workflow needs reliable sync, metadata, cache-control, and upload
ordering. Wrangler remains useful for Cloudflare infrastructure management,
but it is not the artifact transport for this pipeline.

Do not copy these secrets into Coolify. Coolify needs only the public download
URL at web-build time. The proof service and website receive no permission to
publish releases, which keeps a web-service compromise outside the software
update trust boundary.

Sparkle's private EdDSA key is stored in the macOS Keychain under the account
`behu.sh`. It must be backed up securely before moving release automation to a
new Mac:

```sh
SPARKLE_BIN=/tmp/hush-release/SourcePackages/artifacts/sparkle/Sparkle/bin
"$SPARKLE_BIN/generate_keys" --account behu.sh -x /secure/offline/Hush-Sparkle.key
```

The exported file is equivalent to a release-signing password. Never commit or
upload it to R2.

## Publish an alpha

### Release identity

Hush keeps Apple's numeric bundle requirements separate from human prerelease
labels and Sparkle ordering:

| Purpose | Source | Example |
| --- | --- | --- |
| Product milestone | `MARKETING_VERSION` / `CFBundleShortVersionString` | `0.1.0` |
| Tester maturity | `HUSH_RELEASE_SLUG` / `HushReleaseSlug` | `alpha.1` |
| Update order | `CURRENT_PROJECT_VERSION` / `CFBundleVersion` | `10` |

Together these identify the release as `0.1.0-alpha.1 (10)`. Artifacts use the
same identity, for example
`hush-0.1.0-alpha.2-build.11.dmg`. A matching source tag is
`v0.1.0-alpha.1`.

Every build distributed to a tester is an immutable release. Increment both
the prerelease sequence and the globally monotonic build number, even when
shipping several fixes per week:

```text
0.1.0-alpha.1 (10)
0.1.0-alpha.2 (11)
0.1.0-alpha.3 (12)
0.1.0-beta.1  (13)
0.1.0-rc.1    (14)
0.1.0         (15)
```

Use a new `0.MINOR.0` milestone for a substantial pre-1.0 product capability.
After 1.0, use `MAJOR.MINOR.PATCH`: patch for compatible fixes, minor for
compatible features, and major for an intentionally incompatible product or
data-contract change. Commit volume and whether code was written by a human or
an AI assistant never affect the version. User-visible compatibility does.

Apple requires the short version and build fields to remain numeric. The
prerelease label therefore stays in Hush's own build setting and artifact
names, while Sparkle compares the strictly increasing numeric build.

The publisher downloads the live appcast and refuses any build that is not
higher than the latest public build. It also refuses malformed prerelease
labels and a DMG whose filename disagrees with the embedded bundle identity.
This prevents retries or parallel release work from replacing an immutable
tester build.

The current public alpha is `0.1.0-alpha.5 (14)`, with the restored Finder layout.
Alpha.4 was the first notarized download. The next tester release must use a
build number greater than 14.

Build a signed candidate app and DMG for local review. This does not submit to
Apple or publish anything:

```sh
./scripts/build-dmg.sh
```

The outputs are `artifacts/release/export/hush.app` and a versioned DMG under
`artifacts/release/dist`. Reports and build logs are under
`artifacts/release/reports`. The script refuses to overwrite an existing export;
use a new `HUSH_RELEASE_DIRECTORY` for another candidate. Set
`HUSH_TRUST_PINNED_BUILD_TOOLS=1` only after reviewing the pinned Swift macro and
build-plugin packages when Xcode's interactive trust validation is unavailable.
Release packaging requires a logged-in macOS desktop and Finder automation so
`create-dmg` can save the window background, icon positions and size. Packaging
and publishing verify the layout assets and the embedded app's release identity.
Open the final DMG in Finder to review the drag-and-drop layout before submission.
`HUSH_DMG_HEADLESS=1` is allowed only with `release-dmg.sh --local`; those plain
development images cannot pass the public publisher's layout check.

Package, sign, and publish the Sparkle update. Pass the DMG path to also update
the stable website download URL:

```sh
HUSH_RELEASE_DIRECTORY="artifacts/release-alpha5" \
HUSH_DMG_PATH="artifacts/release-alpha5/dist/hush-0.1.0-alpha.5-build.14.dmg" \
  ./scripts/publish-update-r2.sh
```

The publisher performs the safe order:

1. Downloads the existing alpha appcast and archives for delta generation.
2. Creates a metadata-preserving ZIP with `ditto`.
3. Signs the archive and appcast using the Keychain EdDSA key.
4. Uploads versioned archives and delta updates with immutable caching.
5. Uploads `appcast.xml` last with revalidation caching.
6. Optionally uploads both a versioned DMG and `hush-latest.dmg`.

Verify production after publishing:

```sh
./scripts/verify-update-feed.sh
```

## Local update development

Packaging a notarized app and generating an appcast do not require R2:

```sh
./scripts/package-update.sh \
  artifacts/release/export/hush.app \
  /tmp/hush-local-updates/alpha

cd /tmp/hush-local-updates
python3 -m http.server 8088
```

Build a local development app against that feed. Its `alpha.1-local` identity
and unnotarized signature deliberately cannot enter the public packaging path:

```sh
HUSH_UPDATE_FEED_URL=http://127.0.0.1:8088/alpha/appcast.xml \
  ./scripts/build-local-dmg.sh
```

Sparkle is intentionally not started in Debug builds. This prevents a local
development build from replacing itself with an alpha distribution build.

## Submit a reviewed candidate

The updater itself does not change. Configure Xcode signing and store notary
credentials once:

```sh
xcrun notarytool store-credentials HushNotary --team-id 3A22UK7C9L
```

Only after reviewing the candidate, opt in to submission. Submit the final DMG
once; Apple checks the nested app too. Use a new output path so the reviewed
candidate remains available:

```sh
export HUSH_NOTARIZE=1
export HUSH_NOTARY_KEYCHAIN_PROFILE=HushNotary
./scripts/release-dmg.sh --app artifacts/release/export/hush.app \
  --output artifacts/release/final/hush-0.1.0-alpha.4-build.13.dmg
```

Use the actual version, slug and build number in the filename. For another
developer team, set `HUSH_DEVELOPMENT_TEAM` and `HUSH_CODE_SIGN_IDENTITY` before
building. The default is Hush's current team and a Developer ID Application
certificate selected from Keychain.

Submission IDs, Apple logs and postflight reports stay in
`artifacts/notarization` (override with `HUSH_NOTARY_REPORTS`). Waiting defaults
to 15 minutes (`HUSH_NOTARY_TIMEOUT`). A timeout does not cancel Apple's work.
Resume the unchanged artifact with `--resume SUBMISSION_ID`; do not rebuild or
upload it again. An invalid submission requires inspecting Apple's log and
fixing the candidate before a new submission.

The pipeline notarizes and staples the DMG, then staples the exported app with
its ticket from that same submission before creating the Sparkle archive. There
is no separate app submission. Sparkle still verifies its own EdDSA signature,
providing an independent update-chain guarantee.

## Tester experience

- Hush checks for alpha updates automatically.
- Updates download in the background after the tester opts into automatic
  updates.
- Sparkle presents native macOS update UI and lets the tester choose the
  relaunch moment.
- **Check for Updates...** in the Hush menu-bar panel remains the manual fallback.
- An active session is never force-restarted.

Public installers must pass the notarized distribution path. Test the downloaded
DMG on a clean Mac, including an offline launch after stapling. Existing local
Gatekeeper approvals can mask problems; a build-machine launch alone is not
that test. Do not instruct testers to remove quarantine.
