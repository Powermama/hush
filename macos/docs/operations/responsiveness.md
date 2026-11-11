# macOS responsiveness checks

Use Xcode and Instruments, with no diagnostics SDK in the shipping app. Debug
journeys, isolated test-host startup, screenshots and model traces are guarded by
`#if DEBUG`. `scripts/check_assistant_release.py` rejects their markers in Release.
These checks do not submit software to Apple or collect a customer's content.

## Reproduced regression

On 2026-11-04, the native test host reproduced a feedback loop using the production
`TypingActivityMonitor` and `Settings`, an isolated defaults suite, and simulated
permission loss. Before the fix, disabling measurement after a saved typing sample
produced 22,423 settings notifications before the first scheduled assertion ran.
The test requests a 250 ms delay; main-thread starvation means that is not a
precise wall-clock throughput measurement.

Stopping the tap flushed unchanged totals, which published a settings change,
which stopped and flushed the tap again. The fix saves only dirty totals, marks
them clean before publication, suppresses unchanged settings writes, and removes
subscriptions and activation observation on shutdown. Tests cover disabling the
setting, permission loss on activation, shutdown and subsequent changed totals.

This proves a local bug, not the cause of an unobserved M1 Pro freeze. The friend's
random freeze still needs a sample captured while it is happening.

## Native checks

Run from `macos`, using the checked-in dependency resolutions. Approve package
plugins/macros in Xcode, or explicitly pass the skip-validation flags only after
reviewing those pinned dependencies.

```sh
env HUSH_TEST_HOST=1 TEST_RUNNER_HUSH_TEST_HOST=1 xcodebuild \
  -project Hush/Hush.xcodeproj -scheme Hush -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -onlyUsePackageVersionsFromResolvedFile -only-testing:HushTests test
```

`HUSH_TEST_HOST` suppresses model warming, global hotkeys and background services
in the Debug test host. Unlike `HUSH_OPERATION_AB`, it does not enable a model
benchmark. Do not set it for UI journeys, which need app startup.

- Run `HushUITests/HUDNativeGlassJourneyTests` for real AppKit listening HUD,
  native full-screen entry/exit and moving-background material tests.
- Repeat the focused `TypingActivityMonitorTests` and `RecordingHUDLifecycleTests`
  with `-enableThreadSanitizer YES`. Sanitizer overhead is not a production latency
  benchmark; it only detects races on executed instrumented paths.
- Run Product > Analyze (`xcodebuild ... analyze`) for the available static checks.
  Clang analysis does not prove Swift concurrency or GUI correctness.
  The shared scheme analyzes the app; test bundles stay in the Test action so
  Release analysis does not import a non-testable Release module with `@testable`.
- Keep Main Thread Checker and Thread Performance Checker enabled in the Run
  scheme's Diagnostics tab. Profile the actual recording/permission transitions
  using Product > Profile > Time Profiler, then inspect Hangs and the main thread.
  Swift Concurrency is useful for task scheduling and actor contention.

## Remaining manual coverage

Test an actual M1 Pro with its normal apps, microphone route and model choices.
For the HUD, test multiple ordinary desktops, another app's full-screen Space,
Stage Manager, and an external monitor with separate Spaces. The automated
full-screen journey uses a controlled window; it does not certify every layout.

If Hush hangs, Activity Monitor > hush > Sample Process captures thread stacks
while the issue is live. Record Hush build, macOS version, selected models and
whether Accessibility or the audio device just changed. Share that sample only
after reviewing it. Do not enable screen/audio/transcript recording for this check.

The broader source audit found additional paths to profile if hangs persist:
Accessibility reads in selection/destination inspection run on the main actor,
and the audio format recovery path contains a 250 ms synchronous retry delay.
Those paths were not demonstrated as the friend's failure. Avoid changing global
Accessibility timeouts blindly: a timeout must not weaken destination verification
or cause a failed read to be treated as permission to insert text.

## Follow-up review triage

The following source findings from the additional review are not included in the
reproduced hotfix. Timings, peak memory and claims of quadratic growth require
measurement; reading a call site alone does not establish those numbers.

| Finding | Source check | Required reproduction and acceptance |
| --- | --- | --- |
| Changed typing totals still use global settings notifications | Confirmed in `Settings.recordEverydayTyping`; unchanged totals no longer notify | Record a burst of typing with Dashboard open. Separate statistics publication from configuration, preserving time-saved refresh. |
| AX reads can block the main actor | Confirmed in `SelectionCapture` and `FocusedDestinationInspector` | Use a deliberately unresponsive test app; bound total reads and retain fail-closed destination checks. A per-element timeout is not inherited by child elements. |
| Proof transport uses session defaults | Confirmed in `ProvenanceAPI` and `URLSessionProofUploader` | Stall challenge, reservation, upload and completion independently. Bound the overall transaction, cancel network work, and preserve the existing plain-text fallback without a verified claim or late insertion. |
| Qwen loads are deduplicated per model, not globally | Confirmed in `ensureQwenWarm`; eviction does not reset the previous model's state | Concurrent 2B/4B requests with measured memory and active inference. A load lock alone does not release models retained by existing chat sessions. |
| Audio recovery blocks for 250 ms | Confirmed `usleep` in main-actor `AudioRecorder.start` | Fake a route-change failure and test cancellation during recovery; verify real Bluetooth capture before moving engine ownership across queues. |
| Editor retry catches cancellation | Confirmed broad `catch` in `QwenConversationalEditingSession.edit` | Cancel during generation and recovery; verify no second model invocation, retained partial turn, or mutation after Escape. |
| Companion resize follows every published change | Confirmed `objectWillChange` subscription | Measure layouts while recording; separate meter rendering from content-size changes. |
| Icon requests lack in-flight deduplication and a miss cache | Confirmed in `WebsiteIconLoader`; candidate loop is unbounded | Concurrent same-host requests and an HTML page with many failing icons, using a local test server and bounded budgets. |
| Audio duration cap discards `stop()` output | Confirmed in `checkMaxDuration` | Advance an injected clock and verify the captured audio reaches transcription exactly once. |

The remaining review claims about history decoding, clipboard promises, key-store
blocking, catalog refresh and repeated voice downloads require path-specific
reproduction. They are not certified fixed by a passing unit suite or by Xcode's
static analyzer. Do not silently expand this hotfix into a model/audio rewrite.

## Primary references

- [Apple: Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness)
- [Apple: Analyze hangs with Instruments](https://developer.apple.com/videos/play/wwdc2023/10248/)
- [Apple: Overlay collection behavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications)
- [Apple: Accessibility messaging timeout scope](https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout)

Source review is not an independent human review. Tests on one M5 Mac do not
establish reliability or latency on every supported Apple Silicon Mac.
