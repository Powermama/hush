# Development-only assistant diagnostics

These diagnostics exist only under `#if DEBUG`, including the recorder, every call site, model replay types, and menu controls. The production Release binary must not contain them. There is no persistent opt-in preference, network transport, or audio archive. A normal launch does not record assistant turns.

Enable for a development session with `--assistant-diagnostics`, or use the Debug build's menu: **Development diagnostics > Record assistant turns this launch**. Turn it off there, or quit and relaunch without the argument. Turning it off stops accepting late output from already-running recorded turns.

## Evidence per attempt

The local directory is `~/Library/Application Support/Hush/Development/AssistantTraces/<turn UUID>/`.

| File | Meaning |
| --- | --- |
| `trace.json` | Ordered stages and elapsed times, model identity/revision, permissions, actual focused-editor metadata, action choice, validation comparisons, paste dispatch/read-back, cancellation, and typed errors. |
| `transcript.txt` | The recognized command, before generation. |
| `context.json` | Exactly the bounded Accessibility observation passed to the assistant, including whether it found a writable target. |
| `system.txt`, `prompt.json` | The model's actual system/schema input and request payload. These are not private model reasoning. |
| `model-screen.png` | Only the source-window image actually supplied to the model. No image is taken solely for diagnostics and no continuous screen recording occurs. Its absence is meaningful. |
| `model-output.txt`, `reply.json` | Raw generated output, including partial output on failure, and the accepted structured reply if decoding succeeded. |
| `replay.json` | Reconstructable model request with observation, bounded history, time/timezone, model selection, and image-presence requirement. It contains no executable AX handle. |

These files can contain the user's command and visible message contents. They remain local and are not automatically exported. Files are mode 0600 and turn directories 0700. Retention is at most five turns and 20 MiB total, with a 4 MiB per-turn artifact budget and 2 MiB per artifact. Entries older than 24 hours are pruned on the next diagnostic write. Oversized artifacts receive an explicit `artifact.omitted` event; do not treat such a trace as a complete replay.

The diagnostic records source observations and execution decisions. It does not inspect unrelated windows, record microphone audio, or expose hidden model reasoning. Read-back currently records match status and lengths rather than a second full copy of the editor.

## Inspect and replay

```sh
python3 scripts/assistant_trace.py
python3 scripts/assistant_trace.py --content
```

The default output shows the latest trace's stage/error metadata. `--content` explicitly includes captured text. Keep real traces out of source control; use synthetic fixtures for committed regression cases.

To replay only model generation, provide the exact turn directory:

```sh
env HUSH_REPLAY_DIRECTORY='/absolute/path/to/turn' \
  TEST_RUNNER_HUSH_REPLAY_DIRECTORY='/absolute/path/to/turn' \
  xcodebuild -quiet -project Hush/Hush.xcodeproj -scheme Hush \
    -configuration Debug -destination 'platform=macOS,arch=arm64' \
    -skipPackagePluginValidation \
    -only-testing:HushTests/CoworkerReplayTests test
```

Replay calls the local model directly. It never invokes a controller or an executor, pastes text, sends an email, or opens a website. Compare the recorded model snapshot, prompts and runtime with the current source before interpreting differences. Replaying a model response is not a reproduction of Accessibility focus, microphone recognition, or a native paste race. Those require the real destination and their own end-to-end journey.

## Mail incident evidence

The November 1 user report showed a blank Apple Mail compose body with its caret active. Existing system logs show audio capture and Parakeet transcription completed, but the earlier app did not record the assistant's recognized request, model response, or failure stage. No root cause can be established retrospectively from those logs.

The read-only real-Mail probe failed because its Xcode test host lacked Accessibility permission. It did not establish whether the user's installed app was permitted or whether Mail's editor binding failed. The opt-in probe is `HushTests/CoworkerMailLiveTests`, gated by `HUSH_MAIL_LIVE=1` and `TEST_RUNNER_HUSH_MAIL_LIVE=1`; it never writes into the user's draft.

The deterministic UI regression `testDevelopmentTraceExplainsFailedInsertion` injects a missing target into the real controller, then checks that the trace contains the transcript, observed context, model reply, `action.failed`, the actual `unsupportedEditor` error, and a terminal event while leaving the editor untouched. This qualifies the diagnostic pipeline. It is not claimed as reproduction of the user's exact Mail failure. Subsequent user attempts supplied actual Mail evidence, described below.

## Validation and current developer installation

The final focused run passed **38 tests, zero failures or skips**: five diagnostic checks, 12 assistant UI journeys, 10 coworker checks, 10 foundation checks and one native grammar check. Required package tests also passed, including the live local Swift-to-Hono integration. Stale package module-cache warnings were resolved by cleaning the package build cache and rerunning the checks.

The optimized Release build passed. The binary check passed: all four diagnostic recorder markers were absent from Release and present in the installed Debug dylib. [Compact test results](benchmarks/2026-11-01-diagnostics-xctest-summary.json) retain the test evidence after temporary reports are removed.

A subsequent real user attempt supplied the missing evidence: the source application was Apple Mail, the microphone transcript completed, and the model returned a normal answer, but the app's own `AXIsProcessTrusted` result was false. The captured context had zero controls and no editable target. No paste was attempted. The model incorrectly generalized that permission limitation into an inability to write emails directly. Accessibility authorization for the current development build is therefore required before testing insertion. This diagnoses that recorded attempt; it does not retrospectively prove the cause of the unrecorded earlier attempt or establish that insertion will work after authorization. Personal request contents remain only in the local trace, not in this report.

The Debug build was code-signature verified, installed at `/Applications/hush.app`, and launched with `--assistant-diagnostics`. The running process was verified to load its `hush.debug.dylib`; its SHA-256 is `1e193d20d28af75bd3984ef0f20175c6ef28b33580cff63ad0d5b3d6f220ade3`. The previous Release build is retained at `/private/tmp/hush-release-before-diagnostics-20261101.app`. This is a local developer installation, not a distributed release.

Release separation is checked against the built executable, with Debug as a positive control:

```sh
python3 scripts/check_assistant_release.py /path/to/Release/hush.app/Contents/MacOS/hush \
  --debug /path/to/Debug/hush.app/Contents/MacOS/hush.debug.dylib
```

## Follow-up investigation: marker binding and contextual edits

With Accessibility enabled, repeated real Mail requests exposed `AXWebArea`, a missing numeric selection, and a false `changedContext` result before any paste. Apple's public text-marker APIs and WebKit's implementation explain the mismatch. The installed marker adapter then passed a read-only binding check and the user's next paste was read-back verified. A later correction was also verified as an insertion, proving the second defect: the model chose write and the executor appended rather than revised. The schema also lacked a separate subject field.

The [contextual editing foundation](2026-11-01-contextual-editing-foundation.md) records the shared document/field strategy and qualification requirements. New Debug-only Mail checks expose actual marker capabilities and native field associations, and create a separate synthetic draft only when explicitly launched with `--test-mail-editor`. All checks are excluded from Release. The earlier binary hash above identifies that earlier diagnostic build, not the current source.


## Multi-step requests

The first action retains existing artifact filenames. Later actions use `step-2-context.json`, `step-2-replay.json`, and equivalent names for prompts, replies and model screenshots. All steps share the same per-turn byte limit and opt-in Debug-only scope. `scripts/assistant_trace.py --content` includes those text artifacts. The replay snapshot includes completed checkpoints; a checkpoint carries native verification status. Artifact omission due to storage limits is explicit in the trace. Shipping builds contain neither this recorder nor synthetic sequence launch flags.
