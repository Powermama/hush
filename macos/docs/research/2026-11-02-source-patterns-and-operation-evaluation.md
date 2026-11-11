# Source patterns and operation evaluation

Date: 2026-11-02. Source inspection, not a claim that another application's advertised performance transfers to Hush. No third-party execution framework or copied source was added as a dependency.

## Repositories actually inspected

Shallow clones were inspected locally, without running their applications or scripts. Links pin the reviewed source revisions.

| Source | Relevant code | Finding and Hush decision |
| --- | --- | --- |
| [Browser Use](https://github.com/browser-use/browser-use/tree/b49a68e4060acb226da8f784194fef301c53a6d7) | `browser_use/agent/service.py`, `multi_act` | A batch stops after an action declared to change the page, or after a changed URL/focused target. Adapt the observation boundary, not the Python framework. |
| [Pace](https://github.com/HeyPace/pace/tree/6528380b9be5136434c76f6717afcd6494cec616) | `leanring-buddy/CompanionManager+AgentLoop.swift`; `PaceActionExecutor.swift`, `captureLightweight` | Text-only requests can skip screen processing. Lightweight verification avoids repeatedly collecting the full AX tree. Hush already uses selective vision; lightweight polling remains a candidate, not a measured new improvement. Pace also omits tool documentation in some non-agent paths; Hush's per-available-action prompt is our experimental adaptation, not an identical implementation. |
| [Original Clicky](https://github.com/farzaa/clicky/tree/e71105ce091d71dff4d89cf5d8d37ea1df460961) | `leanring-buddy/CompanionManager.swift`, `sendTranscriptToClaudeWithScreenshot` | Explicit screenshot-pixel/display-point conversion, bounded conversation and playback-driven cursor state are useful references. This path captures screens, asks cloud Claude, parses pointing tags, then speaks with ElevenLabs. It is not evidence for reliable local multi-action execution. |
| [DeskMind](https://github.com/deskmind-ai/deskmind/tree/ac985d222ed8e57ce40bfaeb69d5769e776445d6) | `docs/architecture.md` | Distinct perception, decision and native execution roles; model manifests and user-input interruption. Do not adopt its multiple Python services, extra router, or automation dependencies for Hush's first implementation. |
| [DeskMind Hands](https://github.com/deskmind-ai/hands/tree/8d8642f2abb6c8152db3877e26953f560bab2423) | `deskmind_hands/actions.py`, `executor.py` | Bind actions to an observation, app and window. Dispatch and verified outcome are different. Hush already has destination bindings and native receipts; preserve them. |
| [DeskMind Brain](https://github.com/deskmind-ai/brain/tree/dadf97d01512f6384ca8bfd90a77cc88ae1a2f43) | `src/deskmind_brain/router.py`, `heads.py` | Shared operation definitions reduce model/executor disagreement. Its classification-head thresholds are model-specific; do not reuse a probability threshold as confidence in Qwen's prose. |

Correction to an earlier conversational summary: the reviewed original Clicky calls a streaming cloud API, but its callback discards streamed text and the companion waits for the full response before invoking TTS. It does not demonstrate first-sentence streamed speech in this code path.

Do not copy Pace's candidate-click retry policy or treat any visible state change as task success. Such a change can result from the wrong action. Hush keeps action-specific checks and stops after uncertain mutations.

## Implemented experiment

Two native operations reduce avoidable model decisions without guessing future controls:

- `openPage`: resolve an authorized URL, open and verify one new tab, rebind the same browser window, then navigate. No old element IDs survive the tab transition.
- `searchPage`: fill the observed search field, verify the value and focus, then submit once. Read fresh results before choosing a result link.

The controller retains cancellation between substeps, native verification, fresh observations and bounded continuation. New development diagnostics record URL/readiness failures. The browser debug helper now selects a target and executes it against the same captured context, fixing a test-only stale-ID race.

These two operations and their shorter capability-specific prompt are **experimental**. Normal builds keep the prior prompt and available operations. `HUSH_BUNDLED_BROWSER_ACTIONS=1` enables the candidate in a Debug launch only. Release leaves it disabled. No experimental build was installed as part of this evaluation.

## What the tests actually showed

The live pre-change reproduction opened a new Safari tab, then chose a Google web search instead of navigating to the explicitly supplied YouTube URL. The run took 30.757 seconds and ended after an unverified second operation. It did not complete the user's task. See [sanitized trace summary](benchmarks/2026-11-02-browser-before.json).

| Paired synthetic next-decision experiment | Prior interface | Candidate interface |
| --- | ---: | ---: |
| v1, original expanded operation prompt | 8/12 | 5/12 |
| v2, shorter capability-specific prompt | 8/12 | 5/12 |

These are diagnostic regression states with one greedy sample each, not end-to-end success rates. v1 also measured thinking at 7/12 with substantially longer runs; subsequent comparisons disable thinking as requested. v2 includes real generation failures and an attempted retry of an uncertain operation. It is not qualified for default use. [v1 outputs](benchmarks/2026-11-02-operations-v1.json), [v2 outputs](benchmarks/2026-11-02-operations-v2.json).

The initial scoring also conflated efficient bundling with correctness: choosing a valid `fill` instead of `searchPage` was counted as a failure. Some synthetic fixtures exposed external Google search alongside an in-page search field, while native Hush removes that capability. This makes the raw percentages unsuitable for claiming a general accuracy decrease.

[v3 fixtures](benchmarks/2026-11-02-operation-fixtures-v3.json) preserve both interface variants, match that native capability rule, supply page URLs already established by the fixture's receipts, and distinguish **valid next action** from **preferred combined operation**. Initial artifacts are retained, not rewritten. The 12 states are already known regression cases, not a fresh holdout. A stronger claim needs new task states and user-level execution.

The completed v2 Xcode run passed 35 automated checks, including the measurement harness. That means the tests ran and the native contract checks passed; it does not mean all measured model decisions succeeded.

## Native replication and formatting defect

The Python comparison on corrected fixtures found 10/12 valid candidate decisions versus 8/12 with the prior interface. It used MLX-VLM/LLGuidance, 256 output tokens, and reserialized JSON input. Those details differ from Hush's Swift/XGrammar path and 1,536-token cap. It was not valid to assume the result transferred unchanged.

The headless native replication added 16 new cases before evaluating their outputs. Each pair tests missing/present evidence, ambiguous/unambiguous controls, uncertain/verified actions, or intermediate/final operations across English, German and Spanish. No desktop inputs or actions were captured or executed.

| Native Qwen, thinking off | Prior interface: 12 regression states | Candidate: 12 regression states | Prior: 16 new states | Candidate: 16 new states |
| --- | ---: | ---: | ---: | ---: |
| Default grammar formatting | 9/12 | 7/12 | 12/16 | 8/16 |
| Fixed formatting and unescaped input URLs | 8/12 | 10/12 | 11/16 | 10/16 |

The candidate's original-case improvement replicated after the formatting fix, but it still lost one case on the fresh set. Overall 20/28 versus 19/28 is insufficient evidence for promotion, particularly given the fresh-set result. Retain the established prompt and keep combined operations opt-in.

Three failures were not long reasoning: their raw JSON stopped at a colon and then emitted more than 1,000 spaces until the token limit. XGrammar's default `.any` whitespace permits this. `.schema(schema, format: .init(whitespace: .none))` uses fixed separators instead. Whitespace inside quoted draft strings remains allowed. Paired native times:

| Candidate case | Before | After | After validation |
| --- | ---: | ---: | --- |
| music-tab | 37.30 s | 1.89 s | Passed |
| docs-tab | 37.48 s | 2.22 s | Passed |
| stale-target | 37.38 s | 2.85 s | Passed |

Another native response double-escaped a URL copied from escaped JSON input. Context serialization now uses Foundation's `withoutEscapingSlashes`; URL validation stays strict. Formatting and serialization changed together in this run, so aggregate accuracy movement cannot be attributed to one alone. The repeated-space mechanism specifically is prevented by fixed separator grammar. Raw model output and exact native inputs are preserved in [before](benchmarks/2026-11-02-operations-native-v3.json), [after](benchmarks/2026-11-02-operations-native-fixed-format.json) and [native fixtures](benchmarks/2026-11-02-operation-fixtures-native-fixed-format.json).

The controller already stops after an unverified native result. An additional check in `CoworkerProgress.admit` now enforces that invariant at the shared runner boundary, independent of future model adapters. The model's failed uncertain-action answers remain failures in the benchmark; they are not relabeled as model successes because native code blocks them.

Final native checks passed seven executions (six test definitions), including both formatting modes and the shared admission gate. Package tests passed 27 checks, the localhost Swift-to-Hono integration passed, and the full Release build passed with development markers excluded. See [validation and model results](2026-11-02-local-model-comparison.md). No app was installed or launched for normal use during these offline evaluations.

## Qualification rule

Keep one shared observation and action boundary. Change model adapters or action descriptions behind that boundary and compare on identical inputs. Measure valid action/arguments, unsupported claims, duplicate dispatch, completed user tasks, time to first action and time to verified completion separately. A smaller prompt, fewer model calls or a faster first token does not establish higher task success.

New models must pass text decisions, screenshot grounding, Swift runtime compatibility, memory with audio and normal apps, and actual user-level tasks. An image-only benchmark cannot justify replacing the coworker brain. A coordinate-format mismatch belongs in the adapter, not in a blanket conclusion that the model cannot see the screen.
