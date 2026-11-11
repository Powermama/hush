# Local Mac benchmark record - 2026-10-31

These are exploratory component measurements for the [Hey Hush PRD](../../PRD-hey-hush.md), not release qualification or a universal model ranking. Raw JSON includes outputs and failures. No private screen, email, microphone recording, or file contents were used.

The [task-quality follow-up](quality-followup-2026-10-31.md) uses native tools, compares two interfaces, and separates formatting from correct decisions. The [small-model foundation](../2026-10-31-small-model-foundation.md) applies the findings to a 2-4B product design. A measured 9B control is retained for transparency but excluded from the product profile.

## Machine and method

- Apple M5, 16 GiB unified memory, macOS 26.3 (25D125). This is a base M5, not an M5 Pro/Max. No M2/M3/M4 was measured locally.
- Python 3.14.6, MLX 0.32.4, MLX-LM 0.32.2, Transformers 5.22.1; vision additionally uses MLX-VLM 0.7.11 and Pillow 13.0.0.
- Native TTS: Swift 6.3.3 Release build, FluidAudio revision `e15287985625dbf544a343df679436789ffb03fb` (Hush's 0.18.0 checkout), default optimized stage policies.
- Inference jobs ran serially in separate processes. Background desktop applications were uncontrolled; some downloads and file hashing overlapped earlier runs. There was already approximately 9.4 GiB of system swap before the text tests. Power reporting was not a controlled battery/AC protocol. These measurements do not qualify full-stack memory, energy, thermal stability, or a fanless M2.
- Model-file bytes, MLX peak allocations, and maximum process RSS measure different things. Core ML also uses system services. Do not add these numbers together or call them whole-app physical footprint.
- The same small cases were repeated for timing, not to create extra independent quality samples. Use the number of distinct cases when interpreting scores. No statistical confidence interval or p95 claim is justified by three repeats.

## Text generation and action proposals

[bench_mlx.py](bench_mlx.py) runs fixed 512/2,048-token synthetic prompts with 128 generated tokens, batch one, greedy decoding, no prompt-cache reuse. Each shape has one discarded warmup and three measured runs. Random input tokens isolate engine throughput; they do not test language quality. The six action-schema cases and two drafts are separate.

| Model, 4-bit | Artifact bytes, decimal GB | 512-token TTFT, median | Decode, median | 2,048-token TTFT, median | Decode, median | Largest MLX peak in these synthetic runs |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| MiniCPM5-2B | 1.426 | 0.203 s | 79.2 tokens/s | 0.691 s | 73.3 tokens/s | 2.150 GB |
| Qwen3.5-4B | 3.061 | 0.360 s | 45.4 tokens/s | 1.323 s | 43.8 tokens/s | 3.913 GB |
| LFM3-1.7B, MLX-VLM loader adapter | 0.991 | 0.145 s | 105.8 tokens/s | 0.514 s | 107.0 tokens/s | 1.769 GB |

Sources: [MiniCPM5 raw](m5-16gb-minicpm5-2026-10-31.json), [Qwen raw](m5-16gb-qwen35-4b-2026-10-31.json), [LFM3 text raw](m5-16gb-lfm3-text-2026-10-31.json). Artifact bytes include the downloaded weights and processor/tokenizer configuration; they are not compressed network-transfer sizes.

| Smoke configuration | Exact schema plus correct action/target | Material observations |
| --- | ---: | --- |
| MiniCPM5, greedy, thinking off | 4/6 | Wrong German button; returned a label instead of the required element ID. German draft had serious wording/meaning problems. |
| MiniCPM5, temperature 1, top-p 0.95, thinking on | 3/6 | Two cases exhausted the 512-token budget. German email request produced English and missed the specified time. |
| Qwen3.5-4B, greedy, thinking off | 3/6 | Invalid JSON, wrong action on stale context, and wrong target with injected page text. Both draft samples preserved the core meaning better, but were much shorter than requested. |
| LFM3-1.7B, greedy, thinking off requested | 3/6 | Wrong stale-context action, repeated German action objects, and an English draft that entered reasoning and exhausted its budget. |
| LFM3-1.7B, temperature 0.1, top-k 50, repetition penalty 1.1, thinking on | 3/6 | Three action cases exhausted 512 tokens. Both drafts exhausted 768 tokens before finishing reasoning. |

The [MiniCPM sampling follow-up](m5-16gb-minicpm5-recommended-2026-10-31.json) uses its recommended temperature/top-p with seed 0, not a full hyperparameter search. Thinking gets a larger budget; it is not directly comparable on latency to thinking-off. All samples remain in the results. These tests use a generic strict JSON contract, not each model's native tool-call grammar or constrained decoding. They establish integration failures in this harness, not a published tool-use accuracy score.

The [LFM3 sampling follow-up](m5-16gb-lfm3-text-recommended-2026-10-31.json) uses its recommended sampling settings with the same bounded thinking budgets. Its upstream examples permit much longer generation. Failure within these budgets does not establish failure at longer budgets. The text adapter uses the shipped MLX-VLM language implementation and unwraps its logits for MLX-LM generation; conversion/reference parity was not established. Transformers emitted a model-configuration warning during processor loading. Resolve that warning and verify output parity before attributing all failures to the underlying checkpoint.

**Decision:** do not promote MiniCPM5 simply because its throughput is higher. No tested configuration should receive authority to execute raw model output. Constrained schemas, validated element IDs, freshness checks, and deterministic scope enforcement remain necessary. Grammar constraints can fix JSON syntax, not wrong intent or wrong targets.

## Vision: LFM3-VL against Qwen3.5

[bench_vlm.py](bench_vlm.py) generates five clean 960x600 synthetic screens, including a dark email view and a page containing an injected instruction. Eight questions cover reading, absence detection, and pointing. Each candidate uses its own processor defaults, with no thinking, greedy output, a 128-token cap, and no image-feature cache. Two initial warmups precede three runs per case. Image and font hashes are recorded.

| Candidate | Artifact GB | Warm first token, median across 24 runs | Complete response, median | Maximum MLX peak | Strict contract and answer |
| --- | ---: | ---: | ---: | ---: | ---: |
| LFM3-VL-2B MLX 4-bit | 1.609 | 0.270 s | 0.401 s | 2.365 GB | 5/8 distinct cases |
| Qwen3.5-4B MLX 4-bit | 3.061 | 0.676 s | 1.061 s | 4.031 GB | 2/8 distinct cases |

Sources: [LFM3-VL raw](m5-16gb-lfm3-vl-2026-10-31.json), [Qwen vision raw](m5-16gb-qwen35-vlm-2026-10-31.json). These response lengths vary; this is a small pipeline comparison, not a matched decode-throughput test. The first uncached image call took 1.631 s for LFM3 and 1.833 s for Qwen, excluding model loading.

Both models read the five non-pointing answers correctly on manual inspection. Qwen wrapped three correct answers in Markdown fences, which the strict parser rejected. Neither satisfied the requested pixel-coordinate contract for the three pointing cases. This makes the 5/8 versus 2/8 primarily a format-contract result, not evidence that LFM3 reads screens 2.5 times more accurately.

An additional diagnostic asks for `point_2d` coordinates normalized to 0-1000, using English instructions for both models. It was designed after observing the pixel failures and is not a held-out test. Preserve both the original and diagnostic results. Always transform a declared coordinate convention to the actual crop/display; never guess units from the number range.

In that diagnostic, **both models placed all three points inside the correct buttons** on manual inspection. Both still failed the exact schema: LFM3 added a redundant `normalized` property; Qwen returned a bare coordinate array. [LFM3 diagnostic](m5-16gb-lfm3-vl-normalized-2026-10-31.json), [Qwen diagnostic](m5-16gb-qwen35-vlm-normalized-2026-10-31.json). This demonstrates why a model-specific format/coordinate adapter matters. It does not erase the original failures or prove robustness on new screens.

**Decision:** LFM3-VL is the leading compact perception prototype from the candidates measured here. Keep it behind a perception-only interface. Eight clean synthetic cases cannot establish real macOS grounding, prompt-injection resistance, dense-text accuracy, or autonomous computer-use reliability. Python support does not establish Hush's native Swift support.

## Native speech synthesis

[bench_tts.swift](bench_tts.swift) uses the public FluidAudio text-to-complete-PCM APIs, including text normalization and phonemization. Each sentence gets two discarded warmups and three measured runs. Models run separately. No audio playback, listening panel, WER measurement, streaming first-frame measurement, or simultaneous LLM inference was included.

| Same English input | Kokoro ANE v3, median | Supertonic 3 ANE int4, median |
| --- | ---: | ---: |
| Draft confirmation | 65.4 ms | 54.7 ms |
| Download-button location | 64.9 ms | 61.4 ms |
| File-organization preview | 261.1 ms | 118.7 ms |
| Meeting time and email address | 182.8 ms | 113.4 ms |

Sources: [Kokoro raw](m5-16gb-kokoro-v3-2026-10-31.json), [Supertonic raw](m5-16gb-supertonic3-2026-10-31.json). Kokoro uses `af_heart`, version `.v3`, speed 1.0, released hybrid routing. Supertonic uses F1, eight diffusion steps, speed 1.0, ANE-bucketed int4 VectorEstimator. Different voices and durations mean this does not establish equal quality or identical synthesis workload. All generated arrays were finite and non-silent; that alone does not establish intelligibility.

Supertonic's German confirmation took **113.3 ms** warm for 5.51 seconds of audio. Kokoro ANE v3 has no German voice, so no equivalent measurement is reported. First synthesis after initialization took **5.713 s** for Kokoro and **2.516 s** for Supertonic. The longer Kokoro file sentence also took 3.344 s on its first call, consistent with a separate long-input path. Warm more than one shape during preparation and report cold-path latency honestly.

Initialization, including network downloads and preparation, took 49.2 s and 42.4 s respectively. Those are one-off setup observations, not network-independent load benchmarks. Maximum process RSS reached 774 MB for Kokoro and 145 MB for Supertonic; these exclude separate Core ML services and are not complete memory budgets. The downloaded voice asset trees occupied 406.1 MB for Kokoro, including its frontend, and 169.1 MB for Supertonic. These observed installation assets are larger than a bare weight-file headline.

**Decision:** Kokoro through FluidAudio is already fast for brief English replies. Supertonic is a credible smaller multilingual challenger and was faster on the longer inputs here. Qualify pronunciation and license terms, and account for its archived upstream, before making it the production default. Do not replace one voice on parameter count alone.

## Published numbers, separate from our measurements

| Source and test | Published result | What it does and does not support |
| --- | --- | --- |
| [FluidAudio Parakeet Ultra](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/ParakeetUltra.md), LibriSpeech clean/other | Ultra WER 2.13%/3.81%; v3 2.27%/4.12%; Redux 2.71%/5.12% | Keep Ultra for quality. Redux saves storage but is not automatically faster. These are dataset WER values, not command latency. |
| Same source, back-to-back throughput, clean/other | Ultra 126.7x/110.1x realtime; v3 128.6x/114.7x; Redux 83.9x/76.0x | Ultra and v3 are similar in that protocol; compressed Redux was slower. Do not map dataset throughput directly to microphone-release latency. |
| [Liquid LFM3-VL card](https://huggingface.co/LiquidAI/LFM3-VL-2B), vendor GUI category | LFM3-VL 83.1 thinking, 81.5 without thinking; Qwen3.5-4B 81.1; MiniCPM-V 4.7-1B 45.3 | The category aggregates different GUI benchmarks. It is not our MLX 4-bit Mac measurement. |
| Same card, ScreenSpot-Pro / Desktop | LFM3-VL thinking 55.5/94.6; Qwen3.5-4B 50.6/91.6 | Hard professional screens differ substantially from ordinary desktop tests. Neither number is general task success. |
| [Apple runtime benchmark author](https://github.com/john-rocky/apple-silicon-llm-bench), M4 Max Qwen3-8B 4-bit, 512 input/1,024 output, five trials, 2026-06-11 | Core AI 94.1 tokens/s; MLX 90.0 | A roughly 5% decode difference on this matched row, not a universal Core AI advantage. Core AI needs a newer OS than this Mac's 26.3. |
| [Locals authors](https://github.com/Generated-Computers/Locals/blob/main/docs/benchmarks/README.md), M2 Pro 16 GB Qwen3.5-4B, in-process | One request: MLX-LM 61, Locals 64 tokens/s. Eight requests: 87 versus 271 aggregate tokens/s. | The 3.1x headline is batch throughput. It does not make one Hush command 3.1x faster. M2 Pro is not an M2 Air. |

FluidAudio's [historical voice table](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/TTS/Benchmarks.md) reports Supertonic int4 81 ms median complete synthesis and Pocket TTS 26 ms first streamed frame on M5 Pro. These measure different endpoints. Its newer Kokoro v3 49.45 ms figure excludes text processing/G2P. None should be compared directly with this report's text-to-PCM measurements.

## Reproduction and retained artifacts

Create an isolated Python environment and install the versions above. Download model files at the revisions recorded in each JSON. Use local model directories; the harnesses set offline mode and do not enable remote model code. Run from `macos`:

```sh
python docs/research/benchmarks/bench_mlx.py --model /path/to/model --model-id MODEL_ID --output result.json
python docs/research/benchmarks/bench_vlm.py --model /path/to/model --model-id MODEL_ID --fixtures /path/to/temporary-fixtures --output vision.json
```

For the MiniCPM follow-up, add `--smoke-only --temperature 1 --top-p 0.95 --thinking`. For the coordinate diagnostic, add `--normalized-points`. The LFM3 text loader uses `--vlm-text-loader`: MLX-VLM loads the model, a small adapter unwraps its logits, and MLX-LM supplies the same generation loop. Record that adapter when comparing with another runtime.

For the LFM3 follow-up, also add `--smoke-only --temperature 0.1 --top-k 50 --repetition-penalty 1.1 --thinking`. Its default repetition context in this installed MLX-LM version is part of the harness, not proof of exact upstream server parity.

For native voice, create a temporary Swift 6.2 package with macOS 15 minimum, an executable target containing `bench_tts.swift`, and a local FluidAudio dependency at the revision above with `TTS` and `NemoTextProcessing` traits. Build Release, then run each engine in a fresh process:

```sh
TTSBench kokoro /path/to/temporary-model-root kokoro.json
TTSBench supertonic /path/to/temporary-model-root supertonic.json
```

The temporary Python environment, weights, speech assets, fixtures, and native build are disposable. Keep this report, harnesses, model manifests, and small JSON results. Do not delete Hush's installed models or shared user caches. The FluidAudio dependency emitted upstream compiler warnings; the benchmark executable built successfully without changing that pinned dependency.

## Cleanup completed

The [final cleanup receipt](cleanup-final-2026-10-31.json), [first-round receipt](cleanup-round1-2026-10-31.json), and [Granite-source receipt](cleanup-granite-source-2026-10-31.json) record removal of approximately **23.74 GiB of allocated task-owned temporary files across the runs**. This is the cumulative size removed, not a controlled change in system free space. Model downloads, the Python environment, speech assets, native benchmark builds, generated fixtures, and the temporary Clicky snapshot were removed. Hush's installed models and shared/OS-managed caches were not purged.

The [first artifact manifest](artifact-manifest-2026-10-31.json), [second artifact manifest](artifact-manifest-round2-2026-10-31.json), and [Granite conversion record](granite-conversion-2026-10-31.json) preserve revisions and SHA256 hashes. Only small reports, raw results, provenance, and harnesses remain in this directory.
