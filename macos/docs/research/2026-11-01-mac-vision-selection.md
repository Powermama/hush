# Vision model selection for 16 GB MacBooks

Research checked 2026-11-01. Target: M2-M5, 16 GB unified memory, native Hush. This is a source and artifact audit plus a reanalysis of retained measurements. No new inference benchmark or app deployment was performed in this pass.

## Decision

**Keep LFM3-VL-2B MLX 4-bit as the leading separately loaded screen observer from the candidates actually measured.** Its native integration and real-screen quality remain unqualified. Add **UI-Venus-1.5-2B** as the compact, permissively licensed GUI challenger and **Holo3.1-4B** as the main computer-use quality challenger. Do not declare an overall winner before comparing these on the same Mac tasks.

**Use the already downloaded Qwen3.5-4B as the native vision integration baseline.** Its visual weights are present, and Hush's pinned MLXVLM dependency contains the architecture. This can establish screenshot capture, image processing, grounding, and verification without another model download. If used for both perception and writing, describe that configuration as shared weights with separate responsibilities, not two separate models. Never load duplicate text and vision copies simultaneously by accident.

The best configuration is the one that completes supported work correctly within the memory and latency limits. A recent release, high text token throughput, or small download alone does not establish that.

## What is already present

The cached `mlx-community/Qwen3.5-4B-4bit` snapshot is `0e7ffd5c629ef7719d4cbc04069232580bfa9d9c`. Its `model.safetensors` is 3,034,300,695 bytes. Reading only its header found 297 `vision_tower` tensor entries; `config.json` includes `vision_config` and the `qwen3_5` model type. The earlier benchmark counted 3.061 GB of inference artifacts including tokenizer and processor files. These are storage measurements, not RAM requirements.

At the time of this audit, the implementation called `LLMModelFactory` in [LLMRuntime.swift](../../Hush/Hush/PostProcessing/LLMRuntime.swift). The pinned text-only Qwen loader explicitly removes `vision_tower` and `model.visual` keys. [CoworkerContext.swift](../../Hush/Hush/Assistant/CoworkerContext.swift) supplies Accessibility text and explicitly reports that images are unavailable. At that point the project did not link the MLXVLM product. A downloaded multimodal checkpoint therefore does not mean the installed assistant sees screenshots.

At pinned `mlx-swift-lm` revision `bd4b7434e6bdb588c7ef55706ff8904cb7fd4c57`, the VLM registry includes Qwen3.5, Qwen3-VL, FastVLM, and LFM2-VL. It does not include LFM3-VL or MiniCPM-V 4.7. The upstream main registry inspected on this date also lacks those two model types. Architecture registration is necessary but does not qualify a particular conversion's processor, template, weights, or output parity. [Pinned factory](https://github.com/ml-explore/mlx-swift-lm/blob/bd4b7434e6bdb588c7ef55706ff8904cb7fd4c57/Libraries/MLXVLM/VLMModelFactory.swift), [text-only loader](https://github.com/ml-explore/mlx-swift-lm/blob/bd4b7434e6bdb588c7ef55706ff8904cb7fd4c57/Libraries/MLXLLM/Models/Qwen35.swift), [upstream factory](https://github.com/ml-explore/mlx-swift-lm/blob/main/Libraries/MLXVLM/VLMModelFactory.swift).

**Later implementation update, November 1:** the assistant now links native MLXVLM and shares the Qwen3.5 container for text and image inference. A paired-image integration test passed. This establishes image-input plumbing, not general GUI accuracy. See [coworker validation](benchmarks/2026-11-01-coworker-validation.md) and [contextual editing foundation](2026-11-01-contextual-editing-foundation.md).

## Measurements we already have

Recomputed from the retained October 31 JSON, excluding records marked `warmup`:

| Model / MLX 4-bit | Inference artifacts | Median first token | Median complete answer | Maximum MLX allocation |
| --- | ---: | ---: | ---: | ---: |
| LFM3-VL-2B | 1.609 GB | 270 ms | 401 ms | 2.365 GB |
| Qwen3.5-4B | 3.061 GB | 676 ms | 1,061 ms | 4.031 GB |

These were separate Python MLX-VLM processes on a base M5 with 16 GiB, using five synthetic 960x600 screens, eight distinct questions and three measured repeats per question. Answers were very short. Each model used its processor defaults, so this was not a matched visual-token-budget comparison. Background applications were uncontrolled and substantial system swap already existed. MLX allocation excludes other runtime, app, system, and speech memory. These are neither M2 results nor complete speech-to-action timings. [Protocol and limitations](benchmarks/README.md), [LFM3 raw results](benchmarks/m5-16gb-lfm3-vl-2026-10-31.json), [Qwen raw results](benchmarks/m5-16gb-qwen35-vlm-2026-10-31.json).

Both models read the five non-pointing answers correctly on manual inspection. The strict parser accepted five LFM3 cases and two Qwen cases; Markdown wrappers explain Qwen's three extra failures. Neither met the initial pixel-coordinate contract. After a prompt change to explicit 0-1000 normalized coordinates, both located all three tested buttons, but both still violated the exact response schema. That diagnostic reused known examples. It does not establish held-out accuracy. [LFM3 diagnostic](benchmarks/m5-16gb-lfm3-vl-normalized-2026-10-31.json), [Qwen diagnostic](benchmarks/m5-16gb-qwen35-vlm-normalized-2026-10-31.json).

This evidence supports prioritizing LFM3 for latency and memory qualification. It does not support unrestricted visual clicking or a claim that LFM3 is more accurate on real Mac screens.

## Updated shortlist

| Candidate | Why it matters for Hush | Apple deployment evidence | Decision |
| --- | --- | --- | --- |
| LFM3-VL-2B | Small general screen observer; best local latency result above | Publisher MLX 4-bit export; measured in Python; native Swift gap | Leading separate observer, pending qualification |
| Qwen3.5-4B | Vision, contextual answers, and writing in one checkpoint | Installed full checkpoint and native Swift architecture | Integration baseline and quality control |
| UI-Venus-1.5-2B | Trained for GUI localization and navigation; Apache-2.0 | Community MLX 6-bit export, Qwen3-VL architecture | First compact GUI specialist to qualify |
| Holo3.1-4B | Trained for computer use across desktop, browser, and mobile; Apache-2.0 | Community MLX 4-bit export, Qwen3.5 architecture | Main 4B action-quality challenger |
| DeskForge-Qwen3.5-4B v1.1 | Specialization for desktop targets and next actions | Qwen3.5 architecture; no local converted run in this work | Controlled fine-tuning comparison |

**LFM3:** Liquid reports ScreenSpot-Pro 55.5 with thinking and 49.3 without, versus Qwen4B 50.6 in its comparison. Its GUI category average is not a task-completion rate. Its Apple M5 Max hardware chart uses llama.cpp Q4_0 plus an F16 projector, not MLX or a base MacBook. The available MLX export is a separate deployment path. The model uses revenue-conditioned LFM Open License terms, not Apache-2.0. [Model card](https://huggingface.co/LiquidAI/LFM3-VL-2B), [MLX export](https://huggingface.co/LiquidAI/LFM3-VL-2B-MLX-4bit), [license](https://huggingface.co/LiquidAI/LFM3-VL-2B/blob/main/LICENSE).

**UI-Venus:** The 2B variant's published ScreenSpot-Pro result is 57.7; the family's 69.6 headline belongs to 30B-A3B. The inspected 6-bit repository totals 2,476,509,719 bytes, including 2,464,975,767 bytes of weights. The conversion author reports a tied-embedding configuration workaround and weaker precise instruction following than the 8B sibling. Its conversion tests are not a MacBook release benchmark. Do not promise a 4-bit artifact merely because the 6-bit version exists. [Publisher card](https://huggingface.co/inclusionAI/UI-Venus-1.5-2B), [conversion and limitations](https://huggingface.co/mlx-community/UI-Venus-1.5-2B-6bit), [file manifest](https://huggingface.co/api/models/mlx-community/UI-Venus-1.5-2B-6bit/tree/main?recursive=true).

**Holo3.1:** The publisher's small-model chart reports 66.5 ScreenSpot-Pro and 73.1 OSWorld-G for 4B. These motivate a trial, not a ranking against our MLX results. The release also uses an internal OSWorld implementation, so its task-success percentage must not be presented as the official OSWorld-Verified result. The inspected `pipenetwork` 4-bit export totals 3,992,879,691 bytes, including 3,966,047,789 bytes of weights: around 4.0 GB, not 2 GB. Its card records an older vision-model-type compatibility workaround. Check current Swift compatibility and conversion provenance before running it. [Publisher](https://huggingface.co/Hcompany/Holo-3.1-4B), [release and small-model chart](https://hcompany.ai/newsroom/holo3.1), [MLX conversion](https://huggingface.co/pipenetwork/Holo-3.1-4B-MLX-4bit), [file manifest](https://huggingface.co/api/models/pipenetwork/Holo-3.1-4B-MLX-4bit/tree/main?recursive=true).

**DeskForge:** Its v1.1 comparison improves Qwen4B from 30.17 to 49.02 on ScreenSpot-Pro with thinking disabled, greedy decoding, a 128-token output budget, and a 2,097,152-pixel limit. This is a useful within-protocol result for our short-action setting. The older paper's multi-step gains use a fixed 27B planner, which is outside Hush's budget. They do not establish the performance of two local small models. [Model and evaluation](https://huggingface.co/docling-project/DeskForge-Qwen3.5-4B).

The same base Qwen4B scores 30.17 in DeskForge's protocol, 50.6 in Liquid's, and 60.3 in Qwen's own card. Resolution, reasoning, prompting, and evaluation infrastructure differ. Do not combine these into a supposedly controlled leaderboard or attribute the difference to quantization alone. [Qwen evaluation](https://huggingface.co/Qwen/Qwen3.5-4B).

### Other candidates checked

- **Apple FastVLM 0.5B/1.5B:** native Apple demo and efficient visual encoding make it a useful research control. The 85x first-token claim compares against LLaVA-OneVision at a specific high resolution, not current LFM3/Qwen deployments. The released model license restricts use to research and excludes product development, so it is not the Hush product default. [Apple paper](https://machinelearning.apple.com/research/fast-vision-language-models), [native demo](https://github.com/apple-aiml-research/ml-fastvlm/blob/main/app/README.md), [model license](https://github.com/apple-aiml-research/ml-fastvlm/blob/main/LICENSE_MODEL).
- **MiniCPM-V 4.7-1B:** current compact multimodal candidate with an MLX conversion and Apache-2.0 upstream. It remains unmeasured here and absent from Hush's pinned native registry. Liquid's comparison reports only 4.9 ScreenSpot-Pro, so general efficiency claims alone do not justify prioritizing it for dense desktop targets. [Publisher](https://huggingface.co/openbmb/MiniCPM-V-4.7-1B), [conversion](https://huggingface.co/mlx-community/MiniCPM-V-4.7-1B-4bit), [comparison](https://huggingface.co/LiquidAI/LFM3-VL-2B).
- **LocateAnything-3B:** interesting parallel coordinate decoding, but its publisher specifies non-commercial research terms. It is not the production recommendation. [NVIDIA model card](https://huggingface.co/nvidia/LocateAnything-3B).
- **Newer large models:** UI-Venus-2-9B and Holo4's 27B/35B variants exceed the requested model profile. A 35B model with 3B active parameters still stores 35B parameters; its active size does not make it a compact 3B download. [UI-Venus releases](https://huggingface.co/collections/inclusionAI/ui-venus), [H model inventory](https://hcompany.ai/research/models).

## Apple optimization that applies to this product

**MLX Swift/Metal is the preferred native VLM path where the exact architecture is supported.** MLX uses Apple Silicon CPU/GPU execution and unified memory; it does not automatically put a VLM on the Neural Engine. Python MLX-VLM and Swift MLXVLM have different architecture coverage. Core ML compression offers quantization, palettization, and pruning, but an export still needs supported operations, processor parity, and device profiling. Conversion alone is not proof of a speedup or ANE placement. [MLX](https://github.com/ml-explore/mlx), [Core ML optimization](https://apple.github.io/coremltools/docs-guides/source/opt-overview.html).

Recommended engineering choices, pending measurement:

1. Read exact UI text and element identities through Accessibility first. Use Apple Vision OCR for readable text when appropriate, and a VLM for image meaning and missing structure. These inputs complement rather than replace screen vision.
2. Capture the active window on invocation and after relevant state changes. Exclude Hush's own cursor surface. Keep a source-window identity, timestamp, crop origin, pixel size, display scale, and coordinate convention with each observation.
3. Start with a bounded overview and request a relevant higher-resolution crop when small text or a control is ambiguous. Downscaling an entire Retina screen until text disappears saves memory by discarding the information the task needs.
4. Use an explicit image-token and text-context budget. Release image activations after extracting the relevant observation. Cache only against unchanged content and invalidate stale targets before acting.
5. Start with 4-bit language weights where qualified; keep the vision encoder/projector at the precision required for accurate text and target localization. Compare mixed precision against the same higher-precision checkpoint. Do not default to 2-bit compression before a task-quality comparison.
6. Serialize substantial vision/planning work and measure the whole stack with Parakeet and voice loaded. Individual model peaks cannot simply be added to predict residency, and moving speech to ANE does not create a separate RAM pool.
7. Let the observer return bounded facts and target proposals. Native code owns app permissions, current target binding, execution, interruption, and result verification. A predicted point is not a completed edit.

The user-facing interaction remains the Hush cursor plus working state and speech. Vision processing must not introduce a mandatory chat box or a preview/copy/execute form. This is a product requirement, not a capability of a particular model.

## Qualification order

First establish native screenshot-to-answer behavior with the installed Qwen checkpoint. Then run LFM3, UI-Venus, and Holo through the same observation contract. Pin checkpoint, quantization, runtime, processor, prompt, and decoding settings before comparisons. Include DeskForge as a targeted specialization experiment, not an untested default replacement for the writer.

Pre-register held-out Mail, Safari/Chrome, Finder, and editor cases with small text, dark/light themes, overlapping windows, scrolling, Retina scaling, multiple displays, absent/duplicate controls, and English/German requests. Evaluate both screenshot-only and screenshot-plus-AX conditions. Separate text extraction, target hit rate, abstentions, invalid output, and completed task quality. Preserve failures. No model should get credit for selecting the right coordinates when its output cannot be consumed reliably.

Measure cold model load, first uncached image, warm first useful observation, full action latency, p50/p95, process and MLX memory, system pressure/swap change, and sustained battery/thermal behavior. Repeat on a base M2 with 16 GB before promising M2 performance. Keep the PRD's release thresholds; no existing result in this note passes that full gate.

No model weights were downloaded in this research pass. Temporary publisher chart images were removed after inspection; installed Qwen, Parakeet, and Kokoro assets were preserved.
