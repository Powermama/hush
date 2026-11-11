# Desktop assistant source review

Inspected public source on 2026-11-01. These are architectural references, not independently benchmarked replacements for Hush. No third-party implementation was copied into Hush and no additional runtime or model was installed.

## Findings relevant to the current failures

| Project | Verified source finding | Implication for Hush |
| --- | --- | --- |
| [Pace](https://github.com/HeyPace/pace) | Has local planning, OCR, AX targeting, prewarming and stage timing. Its agent loop observes after actions, caps steps, and preserves the original goal. Constrained mutation turns are explicitly single-shot because automatic continuation previously invented follow-ups. | Fresh observations are useful, but adding a loop is not proof of task accuracy. Keep bounded native receipts and measure actual completion. Do not import its automation catalog or multiple planning tiers. |
| [Jason Kneen OpenClicky](https://github.com/jasonkneen/openclicky) | The inspected background-computer-use runtime explicitly throws `runtimeUnavailable`; comments explain that the legacy service was disabled because its server ignored authentication. This does not mean all foreground computer use is disabled. | A feature list or bundled binary is not evidence that a particular control path works. Keep Hush's executor in process, using public AX APIs. |
| [Sonitura](https://github.com/odaysprojects/sonitura) | Documents a screenshot, one schema-constrained action, native input, then another screenshot. Reports about 5 seconds per screen-agent step and 6 seconds for a spoken screen answer. | Useful simple control-loop reference. Its 0.4-second number is dictation, not desktop task completion. Cloud reasoning makes its numbers unsuitable as a local Qwen benchmark. |

Pace's headline is under 500 ms to a spoken answer. However, `TurnBudget.ttfsWMs` measures `sttComplete` to `ttsFirstDispatch`, excluding transcription and not measuring audio playback onset or verified task completion. Its README also describes approximately 500 ms from the planner's first token to audio. These boundaries must not be mixed or treated as a demonstrated M2-to-M5 end-to-end benchmark.

Source revisions and direct links:

- Pace `6528380b9be5136434c76f6717afcd6494cec616`: [loop and exit conditions](https://github.com/HeyPace/pace/blob/6528380b9be5136434c76f6717afcd6494cec616/leanring-buddy/CompanionManager%2BAgentLoop.swift), [latency definitions](https://github.com/HeyPace/pace/blob/6528380b9be5136434c76f6717afcd6494cec616/leanring-buddy/PaceLatencyBudget.swift), [evidence boundaries](https://github.com/HeyPace/pace/blob/6528380b9be5136434c76f6717afcd6494cec616/docs/operations/automation-evidence-matrix.md).
- Jason Kneen OpenClicky `e9eb06a29ff5cd82033d032238f51a936168b05a`: [computer-use runtime](https://github.com/jasonkneen/openclicky/blob/e9eb06a29ff5cd82033d032238f51a936168b05a/cursor-buddy/OpenClickyComputerUseRuntime.swift).
- Sonitura `c448058ca0486e9c81844ad4bc4acc5a1fb95cfd`: [architecture, speed and limitations](https://github.com/odaysprojects/sonitura/blob/c448058ca0486e9c81844ad4bc4acc5a1fb95cfd/README.md). The supplied SYFT8 URL redirects to odaysprojects.

Additional repositories verified as available, without a deep source audit in this pass: [Prasanth OpenClicky](https://github.com/prasanthsasikumar/openclicky), [Samuel](https://github.com/sambuild04/screen-voice-agent), [OpenDex](https://github.com/wassgha/opendex), and [VocaMac](https://github.com/VocaHQ/vocamac). The supplied [original Clicky](https://github.com/farzaa/clicky) URL did not fetch successfully in this pass; do not infer its current availability from the forks.

## Concrete Hush decisions

1. Keep Parakeet, one Qwen text/vision container and Kokoro. The current reproduction found routing and AX-observation failures, not evidence requiring a second planner.
2. Give the active page's controls priority over browser tabs. Verify new tabs using native tab semantics, including Safari's sibling tab buttons.
3. Reserve exact-command shortcuts for genuinely unambiguous commands. Site-specific and contextual searches use the observation loop.
4. Read exposed links and fields without image prefill when those suffice. Retain screenshots for visual explanations and missing page evidence.
5. Measure grammar preparation, prompt/image prefill, generation, native dispatch and verification separately. A visible status does not excuse avoidable latency.
6. Count completed end-to-end goals, wrong destinations, unverified actions and intervention rate alongside p50/p95 latency. Synthetic decision accuracy is a separate metric.

Acceptance requires both a native browser-control check and a real Qwen-driven run. A build, mocked UI test, or successful first tab does not qualify the full YouTube request. No personal message is sent during debugging.
