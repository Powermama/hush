# Checked sequence implementation and decision evaluation

Date: 2026-11-01. Branch: `docs/hey-hush-local-assistant-prd`. Base M5 MacBook Pro, 16 GB unified memory, macOS 26.3, native Swift Debug test host. No additional model was downloaded.

## What was measured

Frozen initial action contract versus the standardized contract, using the same installed Qwen3.5-4B 4-bit model, temperature 0, thinking disabled, 1,536 output-token ceiling. Both conditions received identical synthetic AX observations, goals and checkpoints, at a fixed date/time. Conditions alternated order by case; one separate warm-up preceded scored decisions. The standard condition also narrowed the grammar to native available actions. This tests a combined prompt/schema/capability change, not the isolated causal effect of any one part.

Correct requires the expected next action, target and required arguments, continuation/termination decision, and clarification/document-field behavior where specified. No screens were clicked, no microphone was used and no images were supplied in this evaluation. A correct decision does not establish successful desktop execution. One deterministic sample per case/condition gives limited statistical evidence, and states within a workflow are correlated.

## Results

| Split | Baseline | Standard v1 | Standard v2 |
| --- | ---: | ---: | ---: |
| Development examples (6) | 0/6 | 4/6 | 3/6 |
| Initially held-out states (18) | 10/18 | 7/18 | 14/18 |
| Fresh holdout after the v2 rule was fixed (12) | 7/12 | Not run | 11/12 |

The first revision regressed on unfamiliar tasks. Its complete output is retained. The v2 change clarifies that native verification is automatic and does not require another user-requested action. The original 18 states are regression cases after that change, not unseen evidence. The new 12 states were declared before their outputs were examined.

Across all 36 v2 cases, baseline scored **17/36 (47.2%)**, standard **28/36 (77.8%)**. The fresh holdout increased **7/12 to 11/12**, but this sample is too small to claim 91.7% general desktop reliability. On the six development decisions, v1 was better than v2; neither completed the whole browser journey reliably.

## Latency

Across 36 warm decisions, baseline median **2.480 s**, p95 **2.961 s**; standard median **2.847 s**, p95 **3.288 s** (nearest-rank p95). Accuracy improved with roughly **0.37 s** more median decision latency. These are complete decision times, not TTFT, transcription, speech onset or full action execution. They are Debug measurements, not release-build or M2 performance claims.

The separate initial warm-up including one structured response took **65.10 s** in the final run (71.32 s in v1). Earlier test logs show cached model loading plus ordinary warm-up at about 2.2 s; most of the initial structured-call delay therefore occurred later in the pipeline. The structured-generation dependency builds a cached tokenizer/grammar compiler on first use. This is a supported explanation to investigate, not a separately profiled attribution of every second. Hush now displays **Preparing action controls** before structured generation becomes ready. Initial preparation has a 120-second cap, followed by a 60-second decision cap; the run's 180-second budget still prevents subsequent actions after expiry. No claim that cold response is instant is justified.

## Remaining errors and limits

The v2 errors include premature termination during navigation/search submission, a wrong observed-link ID, an unsupported completion claim, and a proposed repeat of an uncertain export. Native unverified results halt the real loop before another decision, independently of that model mistake. Repeated unchanged proposals, cancellation, stale native bindings, and step/time budgets also block execution. Non-question terminal model prose during continuation is replaced with the last native receipt and a voice follow-up, and that truthful response is retained in history.

The actual Safari/YouTube AX journey is **not qualified** by this evaluation. The opt-in `CoworkerLiveTests.browserSequence` conformance test still records earlier failures and must not be described as passed. Consent/login pages, delayed loads, tab counts with many tabs, multiwindow focus races, real video-result classification and playback remain acceptance work. Arbitrary pixel targeting and general settings transitions are not implied. After validation, the user requested installation for hands-on testing. The previous app was closed, the exact Debug build was installed in `/Applications/hush.app`, and one fresh instance was confirmed running with local development diagnostics. The user is resetting permissions. This installation does not change the live Safari qualification status.

## Reproduction and artifacts

- `CoworkerSequenceEvaluation.pairedDecisions()` uses `HUSH_SEQUENCE_AB=1` and `TEST_RUNNER_HUSH_SEQUENCE_AB=1` in the Xcode test environment.
- Frozen baseline: `Hush/HushTests/CoworkerSequenceBaseline.swift`.
- Case definitions and scoring: `Hush/HushTests/CoworkerSequenceEvaluation.swift`.
- Raw decisions, errors and timings: [v1](2026-11-01-sequence-contract-v1.json), [v2](2026-11-01-sequence-contract-v2.json).
- Aggregates: [summary](2026-11-01-sequence-contract-summary.json).
- Source hashes: [v1](2026-11-01-sequence-contract-v1-sources.json), [v2](2026-11-01-sequence-contract-v2-sources.json).
- UI screenshot: [cursor progress](2026-11-01-sequence-progress.png).

The initial native sequence UI test failed because the old controller stopped after one action. The fixed fixture reaches its second action only after a new capture. The fixture uses native UI with injected model/transcript/executor responses; it is not a real Safari result. Required build, package, integration and final native test outcomes are recorded separately in the verification JSON.

Final checks: **30 native domain/UI checks passed**, followed by a passing rerun of the truthful-history guard; **27 package tests**, **one live Swift-to-Hono integration**, optimized Release build, and Release diagnostic-exclusion scan all passed. The scan used the Debug binary as a positive control. See [verification and cleanup record](2026-11-01-sequence-verification.json).
