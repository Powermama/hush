# Developer ID distribution

Hush distributes directly from its website using Developer ID. An App Store
Connect app record is not required. Notarization is Apple's automated security
check, not App Review and not a guarantee of application correctness.

## Strategy

1. Commit Xcode's generated package resolution. Build with the resolved versions
   only and record the source revision and Xcode version.
2. Archive Release for generic macOS with `ARCHS=arm64`, then export with `method=developer-id`.
   Only the exported app is a distribution input. A plain Release build is not
   sufficient: Code Sign on Copy does not re-sign Sparkle's nested helpers.
3. Check every Mach-O architecture's Developer ID, team, secure timestamp and
   entitlements. Executables require hardened runtime; dylibs do not run as
   separate processes. Verify the complete bundle seal.
4. Run Apple's local distribution assessment. Before submission, only a missing
   notarization ticket is an expected failure. This is not an Apple dry-run:
   server-side checks and acceptance cannot be predicted conclusively.
5. Package the exported app into the DMG, then sign the DMG with Developer ID
   and a secure timestamp. Submit only this outermost container with Keychain
   credentials. Apple also checks the nested app and creates its ticket.
   Persist the submission ID, require `Accepted`, inspect Apple's log, then
   staple and validate the DMG. A timeout resumes the same submission rather
   than submitting again. Do not rebuild or re-sign the accepted DMG.
6. Staple the exported app using the ticket from the same DMG submission and
   validate it. Create the Sparkle ZIP from that stapled app. A ZIP cannot be
   stapled itself. Sparkle EdDSA signing remains independent of Developer ID
   signing. No separate app notarization submission is required.
7. Require final Gatekeeper and stapler checks before publishing. Test a real
   downloaded, quarantined installer on a clean Mac or VM before release.
   Never distribute instructions to remove quarantine as the normal install path.

Keep public upload separate from preparing and notarizing a candidate. Do not
change the app ID, Sparkle key or public appcast to repair code signing. Do not
publish an already distributed build number again.

## Source cross-check

These are primary documentation and source-code comparisons, not an independent
human review or peer-reviewed experimental results. Checked 2026-11-04.

| Source | Practice used | Boundary |
| --- | --- | --- |
| [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) and [custom workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) | Developer ID, hardened runtime, secure timestamps, notarytool, stapling | Only Apple's service can accept a submission |
| [Apple packaging workflow](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution) | Sign nested code, submit only the outermost distribution container, staple it | Hush's drag-and-drop DMG is not a custom installer requiring two submissions |
| [Apple distribution testing](https://developer.apple.com/forums/thread/706442) | `syspolicy_check distribution`, clean-machine download test | Local checks cannot reproduce every recipient machine |
| [Sparkle signing guidance](https://sparkle-project.github.io/documentation/sandboxing/#code-signing) | Archive/export re-signs helpers; preserve nested entitlements | Do not use `codesign --deep` to sign; it is appropriate for verification |
| [UTM packaging source](https://github.com/utmapp/UTM/blob/main/scripts/package_mac.sh) | Explicit export method and separate exported artifact | UTM's QEMU signing exceptions and provisioning are not needed by Hush |
| [CodexBar release source](https://github.com/steipete/CodexBar/blob/main/Scripts/sign-and-notarize.sh) | Staple before final ZIP; distribution assessment after notarization | Hush uses Xcode export instead of copying a SwiftPM-specific signing implementation |
| [Apple Swift package CI](https://developer.apple.com/documentation/xcode/building-swift-packages-or-apps-that-use-them-in-continuous-integration-workflows) | Check in resolved dependencies; reject silent resolution updates | Pinned dependencies improve repeatability, not byte-identical signed output |
| [MLX platform requirements](https://ml-explore.github.io/mlx/build/html/install.html) and [FluidAudio](https://github.com/FluidInference/FluidAudio) | Support Apple Silicon for the current local AI stack | A successful Intel compile is not inference compatibility evidence |
| [Sparkle publishing](https://sparkle-project.org/documentation/publishing/) | Generated arm64 hardware requirement, checked before upload | Older updater clients require migration review |

## One submission or two

Rechecked against Apple's documentation on 2026-11-04: submit Hush's signed
drag-and-drop DMG once. Apple's packaging guidance explicitly recommends the
outermost container, and its custom workflow explains that nested signed code
receives tickets from that submission. Finder styling from `create-dmg` does not
make this a custom executable installer. The two-round exception applies to
third-party installers that install a separately packaged payload, or network
installers and their downloads.

No comparative success-rate or timing evidence was found in Apple's guidance
showing that separately submitting this app before its DMG improves either
outcome. The earlier successful app-then-DMG release is one observation without
a matched control; it cannot establish a speed advantage. Separate submissions
add another upload and completion dependency, so retain the single submission.

[Apple's notary team Q&A](https://developer.apple.com/news/?id=s8eigiyj) explains
that some submissions need additional analysis. Its
[workflow guidance](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
recommends reducing file count, keeping large non-executable data out of uploads,
avoiding heavily compressed images, and checking image integrity. Hush downloads
models separately, uses UDZO, verifies the image on mount, and retains submission
IDs instead of retrying uploads. These reduce avoidable work, but do not guarantee
Apple's processing time or acceptance.

Before signing a release DMG, require the saved Finder layout, the reviewed
background and the Applications link. Repeat these checks before publication.
`check_dmg_layout.py` detects missing assets and mismatched release metadata;
actual Finder visual review still verifies composition. Headless local images
must not enter the public distribution path.

## Credentials

Create an app-specific password under Apple Account > Sign-In and Security.
Enter it at the secure Terminal prompt, never in Git, shell history or chat:

```sh
xcrun notarytool store-credentials HushNotary --team-id 3A22UK7C9L
```

The Developer ID Application certificate and its private key must also be in the
signing Mac's Keychain. The password above authenticates to the notary service;
it is not the signing certificate or Sparkle signing key.

The DMG is signed with the SHA-1 identity of the exported app's leaf certificate,
extracted using `codesign --display --extract-certificates=...`. The fingerprint
selects an identity; it does not select the digest algorithm for the signature.
This avoids ambiguous display names when renewed Developer ID certificates coexist.
Do not delete older identities automatically. The app and DMG preflight both check
team `3A22UK7C9L`, and signing fails if the matching private key is unavailable.

## Acceptance and remaining checks

- Release pipeline rejects Debug/ad-hoc signatures, a wrong team, missing secure
  timestamps, `get-task-allow`, broken seals and unexpected policy failures.
- A preflight success explicitly says the app is not yet approved by Apple.
- Submission IDs and logs remain available when Apple is slow or rejects a file.
- The final DMG has a validated staple and passes Gatekeeper. The separately
  exported app is also stapled and assessed before creating the Sparkle ZIP.
  The app inside the sealed DMG is covered by the DMG's ticket; do not rebuild
  that container just to add a separate app staple.
- Swift package tests, Hono integration and the full Release archive pass.
- Smoke-test MLX, WhisperKit, FluidAudio/Parakeet, Kokoro and Sparkle on the
  exported app before removing a hardened-runtime exception permanently.
- Hush supports Apple Silicon only. Do not produce or advertise an Intel build:
  the MLX inference path requires Apple Silicon on macOS. Prebuilt nested
  frameworks may retain additional signed slices; the app executable is arm64 only.
- Record clean-Mac offline installation as unverified unless actually tested.
  A local signature check does not prove that installation journey.

Apple's queue and first-submission checks are outside Hush's control. Keep model
downloads outside the app bundle, use the default accelerated upload, avoid
unnecessary resubmissions and retain the submission ID. Do not promise a fixed
notarization time or bypass notarytool's preflight with `--force`.

## Check an existing submission

```sh
xcrun notarytool history --keychain-profile HushNotary
xcrun notarytool info SUBMISSION_ID --keychain-profile HushNotary
```

`In Progress` means Apple is still processing; `Accepted` is success. Inspect
the saved Apple log even on success, then validate the distribution with
`check_distribution.py --phase postflight`. Do not submit again just to query
status. If the packaging command timed out, resume the saved DMG submission
with `notarize-artifact.sh --resume SUBMISSION_ID path/to/hush.dmg`, then staple
and check the exported app before building its Sparkle ZIP.

## Alpha.4 distribution record

Published 2026-11-04 as `0.1.0-alpha.4 (13)`, built from clean source revision
`248cffa50b85ddcb9eb0e11121d5cb340fe3b6bb`.

- App submission: `c081de8d-42e6-4588-a75d-608bc665dd17`.
- DMG submission: `b82390a5-462f-40b3-9818-71309f7e0384`.
- Both accepted; Apple logs contain no issues. The separate app submission was
  redundant for DMG distribution and is removed from the subsequent workflow.
- Download: `https://updates.behu.sh/downloads/hush-0.1.0-alpha.4-build.13.dmg`.
- SHA-256: `0763bd7691f4b0690c90212a1c74e681c8217f21a6603083cac37a7264254da5`.
- The public download matched the accepted local DMG byte-for-byte and passed
  signature, Gatekeeper and staple validation. Its mounted app reports build 13
  and passes the Release developer-recorder exclusion check.
- The live Sparkle feed advertises build 13 with the arm64 requirement; its
  EdDSA signature verifies against the packaged update archive.
- A clean-Mac offline installation was not tested. Local assessments are not
  evidence of that end-user journey.

Machine-readable reports remain under `artifacts/release/reports` and
`artifacts/notarization`; signing credentials are not included.

## Alpha.5 distribution record

Published 2026-11-04 as `0.1.0-alpha.5 (14)` from clean source revision
`633dd3ccf95a1447d5d872830fbdc0b3260db44c`. This fixes the plain Finder layout
in alpha.4: the previous headless packaging omitted `.DS_Store`, despite copying
the background image. Release packaging and publication now reject that case.

- Only submission: DMG `dfe0e989-ef35-4282-a425-43af005b896b`.
- Apple accepted it with no issues. Its ticket log covers the DMG, app and nested
  code. The exported app was stapled using that ticket, without an app submission.
- Final Finder layout reviewed and confirmed by the user before submission.
- Public DMG SHA-256:
  `88ace74d03c7492fafdb00f909d50a0bee3bfbdaa4238bcbe9c8aa1f5a1df4a3`.
- Download: `https://updates.behu.sh/downloads/hush-0.1.0-alpha.5-build.14.dmg`.
- The public file matches the accepted artifact and passes Gatekeeper, stapling
  and layout checks. The downloaded Sparkle archive verifies with EdDSA; the
  feed advertises build 14 for arm64. The stable DMG alias uses `no-store`.
- Release-tool tests: 13 passed. Swift package tests: 27 passed. Swift-to-Hono
  integration passed. Release archive and Developer ID export passed.
- A clean-Mac offline installation remains untested. The app code is unchanged
  from alpha.4; this release changes packaging and version metadata.

Reports are in `artifacts/release-alpha5/reports` and `artifacts/notarization`.
