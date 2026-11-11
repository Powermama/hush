# Hush coworker validation - 2026-11-01

The focused Debug run passed **34 tests, zero failures or skips** on an Apple M5 MacBook Pro with 16 GiB and macOS 26.3. The [compact per-test evidence](2026-11-01-coworker-xctest-summary.json) preserves the results without retaining full-screen test recordings. This is prototype integration evidence, not release qualification or a model quality benchmark.

## Reproduction and fixes

The inactive-application UI journey reproduced the reported failure: clicking the cursor's Esc control while another app had focus did not stop it. A native first-click NSButton now handles mouse-down without taking keyboard focus. A second Escape dismisses an already-stopped cursor, which also fades after 1.8 seconds.

The first mouse-follow implementation revealed another defect: the surface could move away during a click or stop following when its own motion placed it underneath a stationary pointer. Following now distinguishes physical pointer movement from the panel catching up. It holds the controls still when the user reaches them. The targeted motion and inactive-app Escape tests passed, followed by the full focused run. Completed actions fade after three seconds. Speech captions follow actual utterance callbacks and clear on interruption.

Release compilation exposed a Swift 6.3.3 optimizer crash in the synthesized deinitializer of a generic NSHostingView subclass. The host is now concrete, with AnyView content, retaining the same first-click behavior. The normal optimized Release build passed with `-skipPackagePluginValidation` for the existing pinned OpenAPI build plugin.

## Test scope

| Checks | Result | What they establish |
| --- | --- | --- |
| 11 AssistantJourneyTests | Passed | Native cursor entry, inactive-app Esc, stopped dismissal, following, idle fade, speech bubble, spoken clarification, direct paste/revision, signature preservation, and stale/cancelled work rejection. Three legacy Mail fixture journeys remain covered. |
| 10 CoworkerTests | Passed | Strict actions, direct navigation routing, cancellation before/after dispatch, spoken turn binding, grounded links, and calendar escaping. |
| 10 AssistantFoundationTests | Passed | Context/fact checks, clipboard ownership, duplicate insertion, chord arbitration, and stale/cancelled result handling. |
| 1 AssistantGrammarTests | Passed | Native XGrammar token masking, Unicode, and complete-output EOS. |
| 2 CoworkerLiveTests | Passed | Installed Qwen text/image inference, Parakeet fixture transcription, and Kokoro synthesis/decode. |
| HushProvenance package | 27 passed | Required existing package checks. |
| Swift-to-Hono integration | 1 passed | Required local service enrollment/publication journey. |
| Optimized Release app build | Passed | Complete arm64 app with the concrete hosting view and native MLXVLM linkage. |
| UI rerun after concrete-host change | 11 passed, no failures/skips | All AssistantJourneyTests rerun after the Release compiler fix, including inactive-app Esc and mouse following. These repeat the same 11 journeys rather than adding new coverage. |

## Installed build

The verified Release bundle was installed at `/Applications/hush.app` and reopened. The application reported running; its installed executable SHA-256 matched the staged build: `1c29e20a7e0938d198fab422101e564aac6bc9c1d3024cfe27e20536c9808813`. `codesign --verify --deep --strict` passed before and after installation. One previous app bundle is retained at `/private/tmp/hush-before-immersive-20261101.app` for rollback. Model downloads were not changed.

The final UI rerun passed all 11 checks on the concrete host. The separate optimized Release app build passed. UI tests use Debug, so these results do not establish Release-mode runtime behavior independently.

The native-vision test uses two otherwise identical requests and synthetic images. Only the left/right red and green rectangles swap. Qwen answers the green rectangle's correct side in both cases. This verifies that pixels reach native MLXVLM and affect the response. It does not measure GUI grounding or real desktop action success.

The real conversation test drafts and revises a meeting reply, transcribes a bundled audio fixture through Parakeet Ultra, resolves a calendar proposal, and synthesizes a decodable local Kokoro reply. An earlier test incorrectly required the name Tom when its request did not require a greeting. The final test explicitly asks for `Hi Tom,` and asks to retain it during revision; the name/time assertions remain. No conversation-quality score is claimed from this small integration scenario.

The UI fixture uses a real NSTextView and native pasteboard, with injected model/transcription output and silent utterance callbacks. It tests the interface and native editing lifecycle, not real microphone accuracy or perceived voice quality. The final focused run took about 126 seconds; per-test durations include setup and must not be used as product latency benchmarks.

## Reproduce

```sh
env HUSH_COWORKER_LIVE=1 TEST_RUNNER_HUSH_COWORKER_LIVE=1 \
xcodebuild -quiet -project Hush/Hush.xcodeproj -scheme Hush \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -skipPackagePluginValidation \
  -only-testing:HushTests/CoworkerLiveTests \
  -only-testing:HushTests/CoworkerTests \
  -only-testing:HushTests/AssistantFoundationTests \
  -only-testing:HushTests/AssistantGrammarTests \
  -only-testing:HushUITests/AssistantJourneyTests test
```

Select the Swift Testing suite, or include parentheses in a method selector. A method selector without parentheses previously selected zero live tests; that run is not live-model evidence. A Release test run also failed because the app module lacked testability; Debug is used above. The normal Release app build remains a separate required check.

## Limits

- Browser New Tab, AXPress, user-pointed clicking, and web-search routing are implemented, but cross-process browser outcomes and permission races still need an end-user qualification matrix. The routing test uses an injected executor.
- ScreenCaptureKit is connected to the source window and native image inference. The paired-image test does not establish successful capture of every real application.
- Multi-step browser research, Premiere pixel navigation, Finder organization, meeting booking, and bulk email are incomplete.
- No 16 GiB M2 speed/memory gate, real microphone/playback cancellation qualification, or held-out model-quality evaluation is established by these tests.
- These are the focused assistant suites, not the entire app UI suite. Existing unrelated settings-journey failures are not claimed as resolved.
- Installed model caches are preserved. Owned temporary test reports and recordings can be removed after compact evidence is retained.
