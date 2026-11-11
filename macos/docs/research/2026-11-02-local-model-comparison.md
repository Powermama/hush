# Local model comparison on the development M5

Date: 2026-11-02. Keep Qwen3.5-4B Q4 as the main model pending stronger evidence. This evaluation tests specific components, not overall desktop-assistant accuracy. Thinking is off throughout the model comparison.

## Method

- Machine: base Apple M5 MacBook Pro, 16 GB unified memory, macOS 26.3. Normal background applications were not controlled. Do not project these timings onto M2 or treat them as full voice-to-action latency.
- Python comparison: MLX 0.32.4, MLX-VLM 0.7.11, Transformers 5.22.1, LLGuidance 1.9.1. Temperature 0, sequential model loading, no cross-request prefix reuse. Warmup recorded separately. Model artifacts are pinned in [the manifest](benchmarks/2026-11-02-model-artifacts.json) and the [preparation script](../../scripts/prepare_assistant_model_benchmark.py).
- Grounding: 100 macOS target queries sampled before predictions from pinned ScreenSpot-v2, balanced 50 text/50 icons. They cover **63 distinct screenshots**, not 100 unique screenshots. Same input image capped at 2 MP; each model's native processor has its own visual-token budget. A hit must fall inside the annotated target box. No model answer is used as ground truth. [Dataset manifest](benchmarks/2026-11-02-screenshot-manifest.json).
- Public benchmark exposure or training overlap is possible. These are positive-target tasks, not tests of absent controls, user intent, prompt injection, scrolling, app focus, or successful clicks. No clicks or messages are executed.
- Decisions: 12 known synthetic regression states, two action interfaces, one sample each, with and without schema masking. Same exact input packets across the three Python-tested brains. Strict valid-action scoring includes arguments, current IDs, available tools, continuation, grounding and response shape. A valid individual step is accepted separately from a preferred combined step. [Packets](benchmarks/2026-11-02-operation-fixtures-v3.json).
- The Python decision budget is 256 tokens. Native Hush uses 1,536; different inference libraries, serialization and grammar settings prevent treating their results as interchangeable. Native replication and 16 fresh states are documented [separately](2026-11-02-source-patterns-and-operation-evaluation.md).

## Completed screen-targeting results

| Model | Hits / 100 | Median seconds | Peak MLX allocated GB | Notes |
| --- | ---: | ---: | ---: | --- |
| Qwen3.5-4B Q4 | 92 | 2.64 | 4.64 | Existing installed checkpoint, normalized x/y |
| Eyes-4B Q4 | 93 | 2.83 | 4.33 | Specialist grounder, normalized x/y |
| Gemma 4 E4B IT Q4 | 45 | 0.82 | 5.78 | Explicit normalized y/x adapter |
| MiniCPM-V 4.7 1B Q4 | 35 | 0.85 | 3.44 | Normalized x/y |

Peak MLX allocation is not total system memory or complete Hush+ASR+TTS memory. These models were measured separately, not resident together.

Eyes corrected four Qwen misses and missed three targets Qwen got right. A net gain of one target on this small public subset does not establish a reliable advantage or justify another resident model. Keep Eyes as a candidate for difficult-screen evaluation, not as a default dependency. Text/icon hits were Qwen 49/50 and 43/50, Gemma 30/50 and 15/50, MiniCPM 22/50 and 13/50. [Eyes outputs](benchmarks/2026-11-02-eyes-grounding.json).

Gemma initially scored 7/100 when required and interpreted as x/y. Inspecting outputs against target boxes revealed predominantly swapped coordinates; a separate rerun explicitly requested y/x and converted it to the common coordinate system, scoring 45/100. The first run is retained as an interface diagnostic. This correction does not mean all Gemma tasks use y/x, or that later coordinate swapping is always appropriate. Its small vision processor has a 280-token budget in this artifact, which also differs substantially from Qwen's image processing. The score characterizes this configuration, not every possible crop/resolution strategy.

[Qwen outputs](benchmarks/2026-11-02-qwen-comparison.json), [Gemma corrected outputs](benchmarks/2026-11-02-gemma-grounding-yx.json), [Gemma first run](benchmarks/2026-11-02-gemma-grounding.json), [MiniCPM outputs](benchmarks/2026-11-02-minicpm-comparison.json).

## Completed Python decision results

Each cell is valid next decisions out of 12, not complete user tasks.

| Model | Prior interface, masked | Candidate interface, masked | Prior interface, unmasked | Candidate interface, unmasked |
| --- | ---: | ---: | ---: | ---: |
| Qwen3.5-4B Q4 | 8 | 10 | 8 | 4 |
| Gemma 4 E4B IT Q4 | 8 | 10 | 0 | 0 |
| MiniCPM-V 4.7 1B Q4 | 1 | 0 | 0 | 0 |

Gemma's masked candidate median was 2.18 seconds, versus Qwen's 2.00 seconds in this Python run. It tied Qwen on correctness here. Its unmasked outputs commonly omitted required fields; MiniCPM also put values in incorrect fields or chose incorrect operations. Those are contract failures, not proof that these models have no general intelligence. Native function-call formats or a different response contract might behave differently, but are not qualified by this test. [Gemma decision outputs](benchmarks/2026-11-02-gemma-actions.json).

Removing all constraints is not the supported optimization: schema masking helped preserve valid response shape. The concrete defect found in Hush was unbounded **formatting whitespace**, not the existence of structured output itself. Fix separators, retain native validation and measure semantics separately from JSON syntax.

## What to keep

1. Qwen remains the main model. Gemma did not beat it on these decision states and lost substantially on whole-screen pointing. MiniCPM is not a drop-in replacement under the tested contract.
2. Keep Parakeet and Kokoro unchanged. This session did not benchmark speech quality or replace the audio engines.
3. Keep Accessibility-based controls and exact native result verification. Screenshot coordinates alone do not establish the correct app, window, document, or action outcome.
4. Keep the fixed-format JSON change: three reproduced native stalls dropped from about 37 seconds to 1.9-2.9 seconds with valid responses. Normal prompt behavior remains established; the new combined-action interface stays behind a Debug flag because its fresh-set accuracy did not beat the prior interface.
5. Enforce unverified-action stopping in the shared runner. Do not rely on a model's promise not to retry, and do not relabel model mistakes as correct predictions because the executor blocks them.

## External evidence and compatibility

The [Gemma model card](https://ai.google.dev/gemma/docs/core/model_card_4) distinguishes E4B's effective parameter count from its larger total including embeddings. Our downloaded Gemma weights occupy about 5.15 GB, MiniCPM about 2.67 GB, and Eyes about 3.31 GB. Weight size is not runtime memory.

[Eyes' published results](https://github.com/deskmind-ai/eyes/blob/391b6af7224326087edae1b514452aca8190f0fb/docs/results.md) report 50.9% on ScreenSpot-Pro for their Q4 MLX Mac configuration, versus 67.7% for full-precision GPU inference. The Mac run used an M4 Pro with 48 GB, a different benchmark and some concurrent load. Neither number predicts our M5 result or task completion. Their resolution experiment supports testing crops/resolution rather than assuming model name alone determines grounding quality.

The installed Swift runtime has Gemma 4 model support, but this benchmark uses Python and does not validate Gemma as a Hush provider. MiniCPM-V 4.7's Python support is not proof of a supported architecture in our pinned Swift model registry. Eyes is a specialized coordinate predictor, not a full coworker brain. A new provider must pass the same typed action contract, interruption behavior, app-specific execution tests and full-stack memory checks before installation.

## Reproduction

Use `scripts/prepare_assistant_model_benchmark.py` to retrieve the pinned artifacts into a temporary directory. Run `scripts/benchmark_assistant_models.py` with the paths and options captured in the reports; Gemma's corrected run uses `--coordinate-order yx`. For decisions, supply the pinned packet JSON via `--tasks`; `--tasks-only` avoids repeating images. No desktop automation is performed by either script. Preserve model/input hashes and output reports when removing temporary weights.

The native suite is explicitly opt-in through `HUSH_OPERATION_AB=1` and disables normal app services at launch. The candidate remains opt-in through `HUSH_BUNDLED_BROWSER_ACTIONS=1`, Debug only. Do not enable it in a normal build solely because the original 12-case regression score increased.

## Validation and storage

The focused native contract run passed all seven executions (six test definitions, one parameterized twice); the opt-in tokenizer profiling test was skipped. It covers fixed separators, preserved draft whitespace/Unicode, valid EOS, readable URL serialization, operation gating, and refusal to continue after an unverified receipt. [Xcode summary](benchmarks/2026-11-02-operation-contract-tests.json). Package tests passed 27 checks; the Swift-to-Hono integration passed its one live localhost check. The temporary local service was stopped.

The full Release build passed. `check_assistant_release.py` confirmed development recorder and evaluation-launch markers are absent from Release and present in the Debug positive control. `git diff --check` passed. No warning or error was reported in the final focused native test, package/integration or Release build logs.

The initial expanded grammar fixture used the legacy block schema, whose paragraph content has different constraints. The final check exercises the actual coworker schema changed here; the failed fixture run was not counted as a successful validation.

Removed 12.51 GB of task-owned model downloads, Python environment, cloned source checkouts, synthetic trace scratch space and local service data. Installed Qwen and the application's existing model caches were not removed. Reports, exact inputs, model revisions, hashes and reproduction scripts remain in this repository. [Cleanup ledger](benchmarks/2026-11-02-cleanup.json).

No replacement build was installed or opened during these offline model tests. Actual browser execution after this change still needs a coordinated live check; synthetic decision success is not a claim that the full YouTube task has passed.
