# Hey Hush research - Clicky, compact models, and Apple Silicon

**Researched:** 2026-10-31.

**Use case:** visible, local assistance with email drafts, Finder organization, and short browser tasks on 16 GB M2-M5 MacBooks.

**Related product contract:** [Hey Hush PRD](../PRD-hey-hush.md). **System strategy:** [A strong foundation for 2-4B models](2026-10-31-small-model-foundation.md).

This report combines source inspection, current primary documentation, and [local M5/16 GiB component benchmarks](benchmarks/README.md). No candidate was measured on an M2, and no complete assistant was qualified. Recommendations below reflect the measured failures as well as speed. Parameter count, compressed file size, runtime memory, and whole-app peak memory are different quantities.

## 1. What Clicky actually supplies

Inspected public source revision: [`e71105ce091d71dff4d89cf5d8d37ea1df460961`](https://github.com/farzaa/clicky/tree/e71105ce091d71dff4d89cf5d8d37ea1df460961). A temporary source snapshot was used to search all Swift and worker files.

| Evidence | Finding and implication |
| --- | --- |
| [README](https://github.com/farzaa/clicky/blob/e71105ce091d71dff4d89cf5d8d37ea1df460961/README.md) | The public repository is the earlier MIT-licensed companion; newer development is private. It is not the source of every current HeyClicky feature. |
| [CompanionManager.swift](https://github.com/farzaa/clicky/blob/e71105ce091d71dff4d89cf5d8d37ea1df460961/leanring-buddy/CompanionManager.swift) | Push-to-talk transcript and screenshots feed a streamed Claude response; the result supplies speech and a pointing tag. Session history is retained. This demonstrates contextual conversation, not verified task execution. |
| [CompanionScreenCaptureUtility.swift](https://github.com/farzaa/clicky/blob/e71105ce091d71dff4d89cf5d8d37ea1df460961/leanring-buddy/CompanionScreenCaptureUtility.swift) | Captures connected displays, excludes its own windows, resizes to a maximum dimension of 1,280, and tracks screen coordinates. Hush should reuse the coordinate lessons while minimizing capture scope. |
| [ElementLocationDetector.swift](https://github.com/farzaa/clicky/blob/e71105ce091d71dff4d89cf5d8d37ea1df460961/leanring-buddy/ElementLocationDetector.swift) | Requests a Computer Use response, then extracts a point. The presence of a `left_click` response is not an implementation of a general clicking agent. |
| [Worker](https://github.com/farzaa/clicky/blob/e71105ce091d71dff4d89cf5d8d37ea1df460961/worker/src/index.ts) | Proxies chat, speech synthesis, and transcription-token requests. Local inference removes the need for these services. |
| [ClickyAnalytics.swift](https://github.com/farzaa/clicky/blob/e71105ce091d71dff4d89cf5d8d37ea1df460961/leanring-buddy/ClickyAnalytics.swift) | Analytics payloads include transcript and response strings. Replacing model providers alone does not make this code private/offline. |

The current [HeyClicky website](https://www.heyclicky.com/) describes screen-aware talk, drawing/pointing, and agent tasks. Those are product claims, not independently tested capabilities in this review. Hush should preserve contextual invocation and visible assistance while making its supported outcomes much narrower.

## 2. Recommended complete stack

Select for successful short Mac tasks per unit of memory, energy, and waiting time. The user excludes a 9B product model; target a 2-4B planner/writer and improve context, tool interfaces, workflows, and verification. The final prototype recommendation is deliberately different from the initial catalog and from the supplied single-VLM diagram:

| Component | Prototype choice | Evidence and remaining gate |
| --- | --- | --- |
| Speech recognition | Existing Parakeet Ultra, FluidAudio/Core ML | Keep the requested multilingual engine. Redux is the storage option, not a proven speed upgrade. |
| Reasoning and writing | Qwen3.5-4B MLX 4-bit as the integration baseline | Native-tool correct decisions improved from 25/54 to 35/54 with named tools. German writing and state/scope failures remain; no release planner is qualified. |
| Visual perception | LFM3-VL-2B MLX 4-bit for qualification | On the same synthetic screens, median response 0.401 s and peak MLX allocation 2.365 GB, versus Qwen4B 1.061 s/4.031 GB. Both read the five factual answers correctly; format and coordinate adapters remain essential. |
| English spoken output | Kokoro 82M, FluidAudio ANE v3 | Native measured short replies around 65 ms complete PCM. Preserve the optimized hybrid stage routing. |
| Multilingual spoken-output challenger | Supertonic 3 ANE-bucketed int4, FluidAudio | Measured 55-119 ms on four English inputs and 113 ms on one German input. Smaller observed assets/RSS, but no listening-quality verdict and archived original upstream. |
| Context and execution | AXUIElement, browser DOM, ScreenCaptureKit crops, deterministic native adapters | Exact element identities and native postconditions carry execution authority. Models propose; they do not control the machine directly. |

This is a **prototype selection**, not a claim that Qwen is the world's best small model or that the entire stack is ready to ship. LFM3 is open weights under a revenue-conditioned license, so this profile is not uniformly permissive open source. If permissive weights are a hard requirement, retain Qwen vision as the control and qualify MiniCPM-V 4.7 separately. The user approved research/testing, not a license decision for distribution.

The local tests changed the recommendation: MiniCPM5 was faster and smaller than Qwen, but its German writing and short-budget behavior did not justify promotion. LFM3's separate 1.7B text model is even smaller and fast, but also produced format, target, and generation-budget failures in the tested MLX pipeline. Native parser, sampling, conversion/reference parity, and held-out task evaluation are needed before judging the models' ultimate capability. Do not select a default merely from vendor scores or total parameter count.

Keep perception and reasoning as separate responsibilities with independent lifecycles. Do not keep both heavy engines generating concurrently. Parakeet remains the sole new-mode ASR path, with Hush's existing WhisperKit language fallback preserved. No Moonshine is added. Kokoro v3 does not provide German; qualify Supertonic or a larger Pocket language pack for German spoken replies.

## 3. Why these models, and what could beat them

| Candidate | Primary evidence | Decision |
| --- | --- | --- |
| **MiniCPM5-2B** | [Card](https://huggingface.co/openbmb/MiniCPM5-2B): 2.52B total parameters, agent training and on-policy distillation. [Official MLX files](https://huggingface.co/openbmb/MiniCPM5-2B-MLX/tree/main): approximately 1.43 GB. [Config](https://huggingface.co/openbmb/MiniCPM5-2B-MLX/blob/main/config.json): standard Llama, affine 4-bit, group size 64. | Measured fast, but not promoted: German draft and strict action failures in the local pipeline. Vendor benchmark gains do not establish short-budget or 4-bit quality. |
| **LFM3-1.7B** | [Card](https://huggingface.co/LiquidAI/LFM3-1.7B) and [release](https://www.liquid.ai/blog/lfm3): compact hybrid architecture and strong vendor agent results. The reported quality comparison uses BF16/vLLM and long contexts. | Measured compact alternate planner; local pipeline failures block promotion. Keep as an efficiency candidate after runtime/prompt parity checks, not a release winner. |
| **MiniCPM-V 4.7-1B** | [Card](https://huggingface.co/openbmb/MiniCPM-V-4.7-1B): early encoder compression and 4x/16x visual-token modes, Apache-2.0. [GGUF artifacts](https://huggingface.co/openbmb/MiniCPM-V-4.7-1B-gguf/tree/main): Q4_K_M about 672 MB plus the 4x FP16 projector about 901 MB. | Permissive-license challenger, approximately 1.57 GB for those two files. Not locally benchmarked. LFM3 is now the leading measured perception candidate; generic visual scores cannot establish GUI superiority. |
| **LFM3-VL-2B** | [Card](https://huggingface.co/LiquidAI/LFM3-VL-2B) and [MLX 4-bit export](https://huggingface.co/LiquidAI/LFM3-VL-2B-MLX-4bit) supply a newer compact visual alternative, with vendor GUI evaluations. | Leading measured perception prototype, subject to model terms and native runtime qualification. Dense UI, real apps, and held-out grounding remain untested. |
| **Gemma 4 E2B QAT** | Google's [card](https://huggingface.co/google/gemma-4-E2B) lists 2.3B effective parameters and 5.1B including embeddings. [QAT deployment](https://blog.google/innovation-and-ai/technology/developers-tools/quantization-aware-training-gemma-4/) is designed around low precision. | Main quantization-aware challenger. Specify the exact text-only/full-vision export; the smallest advertised variant is not the complete multimodal model. |
| **Granite 4.2 3B** | [IBM card](https://huggingface.co/ibm-granite/granite-4.2-3b): Apache-2.0, tool calling, controllable reasoning, and tested German among 12 languages. | Measured challenger: 29/54 correct decisions with named tools, substantial extra prose and German factual errors. Its local 4-bit-base conversion actually averages 5.985 bits per weight. Not promoted. |
| **Nemotron 3 Nano 4B** | [NVIDIA card](https://developer.download.nvidia.com/assets/ace/model_card/Nemotron_3_Nano_4B.pdf): compressed from a 9B parent, hybrid Mamba/attention, English-focused. | Useful distillation/runtime comparison; not first choice for a multilingual assistant without a demonstrated quality advantage. |
| **Qwen3.5 2B/4B and Qwen3-VL 2B** | [Qwen3.5](https://huggingface.co/Qwen/Qwen3.5-4B), [Qwen3-VL](https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct), existing Hush loaders. | Qwen4B is the integration baseline for improving the surrounding system, not an endorsed release writer. The measured 9B control is excluded from the product profile at the user's request. |
| **SmolVLM2 500M / Apple FastVLM** | [SmolVLM2](https://huggingface.co/HuggingFaceTB/SmolVLM2-500M-Video-Instruct) is very compact. [FastVLM model terms](https://github.com/apple-aiml-research/ml-fastvlm/blob/main/LICENSE_MODEL) exclude product development. | SmolVLM is a minimum-footprint experiment; FastVLM is research-only under those published terms. Neither is an automatic product choice. |

The [LFM Open License](https://huggingface.co/LiquidAI/LFM3-1.7B/blob/main/LICENSE) defines a $10 million annual-revenue threshold and conditions commercial rights on it. Treat LFM as open weights under its specific terms, not as interchangeable with Apache-2.0/MIT. Do not describe all downloadable models as open source.

Native compatibility was inspected separately from model availability. MiniCPM5's `llama` configuration has a loader in Hush's [MLX Swift LM 3.31.4 registry](https://github.com/ml-explore/mlx-swift-lm/blob/3.31.4/Libraries/MLXLLM/LLMModelFactory.swift). It still needs template, stop-token, and XML-style tool-call validation. Neither LFM3 nor MiniCPM-V 4.7 appears in the corresponding pinned registries. Python MLX-VLM 0.7.11 successfully loaded LFM3 in this research. For the native app, qualify an upstream MLX Swift loader or embed a validated llama.cpp/Metal build; Liquid recommends b11960 or newer for LFM3-VL. A GGUF export is a different artifact requiring fresh tests. Do not transfer Python MLX results to Swift or llama.cpp.

Use accessible text and DOM before images. Apple's [Vision OCR](https://developer.apple.com/documentation/vision/recognizing-text-in-images) can complement the VLM. Keep exact element strings and IDs; ask perception only for missing information. A deterministic file-type move plan does not require a screenshot or prolonged reasoning.

## 4. Speech decisions

### Speech recognition

Keep **Parakeet Ultra** as requested. Hush records about 603 MB for Ultra and 210 MB for Redux; both use its existing FluidAudio path. These are download sizes. Measure short commands, German/English code switching, filenames, accents, and noise without changing the existing dictation default. [FluidAudio ASR](https://github.com/FluidInference/FluidAudio#automatic-speech-recognition-asr--transcription).

Moonshine was investigated, not adopted. Its [model table](https://moonshine-voice.readthedocs.io/en/latest/models/available-models/) lists compact MIT streaming models, and its [macOS integration](https://moonshine-voice.readthedocs.io/en/latest/using/adding-the-library/) provides a native Swift package. However, its [published benchmark method](https://moonshine-voice.readthedocs.io/en/latest/using/benchmarks/) principally compares CPU streaming with Whisper. It does not demonstrate that Moonshine beats Hush's Core ML/ANE Parakeet configuration. Adding a second ASR engine without that evidence is not justified. No Moonshine dependency or model should be installed for this feature.

### Speech output

Choose **Kokoro 82M with FluidAudio's ANE v3 path** as the initial English voice. This is a concrete Apple runtime decision, not simply retaining a familiar model name. [FluidAudio's v3 documentation](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/TTS/KokoroAne.md) describes a hybrid CPU/ANE, GPU, and Accelerate pipeline, available from macOS 15. Select `version: .v3` explicitly; the default remains legacy. Its fast decoder path covers short audio, while longer utterances fall back to a different path. Avoid overriding every stage to `.all` or assuming ANE-only placement. Qualify the exact OS and language.

[Kyutai's October release](https://github.com/kyutai-labs/pocket-tts) provides 18.2M, 6.9M, and 1.9M English models including their decoder. Compare **18.2M** against Kokoro first; compare **6.9M** for Compact. Smaller weights and streaming do not establish better pronunciation or lower complete-utterance latency. Larger language-specific Pocket models cover German and other languages; those are separate downloads and measurements.

The inspected FluidAudio checkout at `e15287985625dbf544a343df679436789ffb03fb` contains `PocketTtsSmallManager`, `.english18m`, `.english7m`, streaming sessions, and cancellation. It defaults to Core ML CPU/Neural Engine execution with an FP32 CPU Mimi decoder. Keep that decoder precision: the [upstream implementation notes](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/TTS/PocketTTS.md) report audible noise with the faster fused FP16 path. Small-model packs span roughly 34-145 MB; inspect the chosen manifest rather than labeling parameter count as MB. Complete first-run compilation during setup.

[Kokoro's card](https://huggingface.co/hexgrad/Kokoro-82M) describes 82 million parameters, not an 82 MB installation. Also compare [Paradee](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/TTS/Paradee.md) if extreme footprint matters. Phonon 31M has a native path in the same checkout and warrants a pronunciation comparison, but its independently retrievable upstream artifact was unresolved in this review. [Supertonic](https://github.com/supertone-oss-archive/supertonic) was archived on September 9, 2026. It nevertheless ran successfully through FluidAudio on this Mac and is the measured multilingual challenger. Its code and weight licenses differ; record the exact checkpoint terms. Paradee's current documentation lists four voices, not the single voice in the supplied recommendation. No Paradee or Pocket model was locally benchmarked in this session.

The [local voice comparison](benchmarks/README.md#native-speech-synthesis) includes both Kokoro v3 and Supertonic int4, not just published numbers. Kyutai's current [Pocket model card](https://huggingface.co/kyutai/pocket-tts) lists CC-BY-4.0 and gated access conditions; the supplied blanket research-license statement should not be copied. Check the specific Small/language/conversion artifact terms independently. LocalVQE is an optional noise-cleanup experiment, not a default extra stage: no measured command-recognition benefit was established here.

Test brief confirmations, email addresses, filenames, dates, currency, abbreviations, interruption, and long-text chunk boundaries. Score intelligibility and meaning preservation before voice preference. TTS is optional; stopping speech must not stop visual progress or hide errors.

## 5. Compression: what is useful now

### Weight quantization

Start with established 4-bit groupwise quantization. Idealized 4B FP16 weights occupy 8 GB; idealized 4-bit weights occupy 2 GB. Real artifacts also include scales, unquantized layers, embeddings, vision components, and metadata. Runtime adds activations and caches. These calculations illustrate storage, not measured memory requirements.

Current [MLX quantization documentation](https://ml-explore.github.io/mlx/build/html/python/_autosummary/mlx.core.quantize.html) lists affine, MXFP4, MXFP8, and NVFP4 formats. The availability of a format does not prove a latency advantage on M2. Compare accuracy and latency using the exact model, hardware, kernel, and runtime revision. Current MLX documentation may be newer than Hush's dependency pin.

Use higher precision for sensitive layers if measured errors justify it. Evaluate 3-bit only after the 4-bit baseline passes. Do not apply 1/2-bit post-training compression to an arbitrary model and assume that a natively low-bit-trained model's results transfer.

### Quantization-aware training and distillation

Google's [Gemma 4 QAT release](https://blog.google/innovation-and-ai/technology/developers-tools/quantization-aware-training-gemma-4/) is directly relevant: training anticipates lower-precision deployment. Its sub-1-GB example is a text-only E2B configuration without per-layer embeddings, not a complete visual agent. Match the checkpoint to the intended quantization format; simply converting it to an arbitrary 4-bit layout may not preserve the advertised behavior.

Distillation makes a genuinely smaller student. Paradee is a concrete speech example. For Hush's planner, task-specific distillation or fine-tuning is a later option if held-out errors show a stable gap. It requires licensed data and independent validation; do not train on users' screens or emails by default.

### Core ML palettization and ANE execution

Apple documents [palettization and compression](https://apple.github.io/coremltools/docs-guides/source/opt-overview.html), a [staged optimization workflow](https://apple.github.io/coremltools/docs-guides/source/opt-workflow.html), and [performance tradeoffs](https://apple.github.io/coremltools/docs-guides/source/opt-palettization-perf.html). Weight-only quantization and grouped low-bit lookup tables can reduce storage. Calibration or training can recover quality when simple conversion degrades it.

Core ML execution depends on model operations, shapes, OS, and device. A small file does not prove ANE execution or lower inference latency. MLX uses CPU/GPU paths; it does not automatically run a model on the Neural Engine. Prefer Core ML for proven speech/encoder paths and MLX for the flexible planner/VLM path. Profile the complete pipeline before moving components between runtimes.

### Context-cache compression, including TurboQuant

[Google's TurboQuant research](https://research.google/blog/turboquant-redefining-ai-efficiency-with-extreme-compression/) targets vector and KV-cache compression. It does not shrink all model weights or make total app memory six times smaller.

The [MLX-VLM implementation](https://github.com/Blaizzy/mlx-vlm#turboquant-kv-cache) reports one Qwen3.5 4B, 128K-context example with KV memory falling from 4.1 GB to 0.97 GB while peak memory falls from 18.3 GB to 17.3 GB. That upstream example illustrates why cache savings cannot be substituted for process savings; it is not a Hush benchmark. Other examples show latency tradeoffs. Cache types and kernels also affect compatibility.

Hush starts with roughly 4K bounded context, so first avoid retaining irrelevant screen content. Only evaluate advanced KV compression after measuring cache pressure. Verify native Swift implementation, recurrent/sliding cache behavior, cancellation, and output quality. A Python `mlx-vlm` flag does not automatically exist in Swift.

### Other useful optimizations

Crop to the relevant region, cap image tokens, batch file metadata, cache unchanged observations, and expose only the current capability's tools. These reduce inference work without discarding model precision. Do not shrink screenshots until labels disappear.

Speculative decoding is a latency experiment, not model compression: a draft model can add memory and overhead. An [October 2026 Apple Silicon study](https://arxiv.org/abs/2610.31479) found that all speculative methods in its tested single-request workload reduced throughput. That is not a universal impossibility result, but it rules out assuming server-GPU speedups transfer. Keep DSpark and other draft models out of the default profile until a matched Hush test shows a gain. No large sparse/MoE model qualifies for a 16 GB laptop solely because its active parameter count is small.

For MiniCPM-V, encoder/token compression can reduce work before the language model sees the image. Use its 4x projector for small UI text first, then compare 16x on the same extraction cases. This trades visual detail against inference work; it is different from lowering weight precision. A compressed model that misreads a filename is not an improvement for Hush.

## 6. Runtime decision

| Technology | Role and limitation |
| --- | --- |
| [MLX Swift LM](https://github.com/ml-explore/mlx-swift-lm) | Preferred planner runtime, with low-bit Metal kernels and native Swift integration. A supported architecture is necessary but does not validate a model's template or tools. |
| Core ML + [FluidAudio](https://github.com/FluidInference/FluidAudio) | Parakeet ASR, Kokoro ANE v3 voice, and the measured Supertonic int4 challenger. Preserve component-specific compute units, then profile actual device placement. |
| [llama.cpp + Metal](https://github.com/ggml-org/llama.cpp), [multimodal support](https://github.com/ggml-org/llama.cpp/blob/master/docs/multimodal.md) | Native C/C++ option for LFM3 or MiniCPM-V when MLX Swift lacks a supported loader; also a planner comparison. Pin model/projector compatibility and embed behind a Swift interface. |
| [Apple Core AI](https://developer.apple.com/videos/play/wwdc2026/324/) | Newer deployment framework with specialization, memory control, and CPU/GPU/ANE paths. Evaluate on supported newer OS versions; do not assume it is available on the macOS 15 baseline or accepts every checkpoint without conversion. |
| Python MLX-LM / MLX-VLM | Research conversion and benchmarking tools; not a required production daemon. Record gaps before porting results into Swift. |
| Apple Foundation Models/system voices | Optional proprietary platform alternatives, outside the requested open-model baseline. Local does not mean open source. |

The production design is a native Swift app with **MLX Swift reasoning, a validated native Metal perception backend, and Core ML speech**. Prefer a supported MLX Swift vision loader; embed llama.cpp when it supplies the better supported native path. Benchmark that selected backend before claiming the Python prototype's speed. MLX is an inference framework, not a competing model or an automatic compression guarantee. No official Apple runtime named "VX" was identified; confirm a specific product link if a different technology was intended. No account, API key, local web server, or Python process is required for the shipping mode.

Apple's [WWDC26 MLX session](https://developer.apple.com/videos/play/wwdc2026/232/) describes newer kernels using M5 GPU Neural Accelerators for prompt processing. These accelerators are distinct from the dedicated ANE used by Core ML. M2-M4 do not inherit M5-specific speedups. Compare chip generations separately and verify the runtime/OS requirements of each optimized kernel.

## 7. Corrections to the supplied proposal

- A local companion is feasible to investigate on 16 GB; universal autonomous computer use and essentially instant responses are not established.
- The public Clicky pointer demonstrates guidance. Execution, app adapters, target validation, rollback, and completion checks are additional product work.
- Accessibility context is highly valuable but incomplete in some apps; browser DOM access has its own permissions and lifecycle.
- Separate perception and reasoning as requested. A single VLM diagram is an alternative architecture, not the agreed Hush design.
- All engines share unified RAM. ANE placement can reduce GPU contention, not eliminate memory consumption.
- Disk sizes and parameter counts are not interchangeable with runtime memory. Compute the complete profile, including speech frontends and compiled caches.
- Select Kokoro's updated Apple runtime for initial voice and compare Pocket Small as a compact streaming alternative. Parakeet stays: the research does not demonstrate that another ASR engine improves the existing path.
- FastVLM's published model terms exclude product development. LFM models and Supertonic also have model-specific terms; do not label every downloadable checkpoint permissive open source.
- A local AI claim must distinguish model downloads, app updates, browser traffic, mail sync, and Hush's existing opt-in proof service.

## 8. Measurements and remaining qualification

The [benchmark record](benchmarks/README.md) includes actual M5 text, vision, and native TTS measurements. The [native-tool follow-up](benchmarks/quality-followup-2026-10-31.md) adds 18 cases over three seeds, separate format/decision metrics, German/English draft inspection, and published BFCL/IFEval/GUI comparisons. The [foundation strategy](2026-10-31-small-model-foundation.md) converts the observed errors into a testable 2-4B architecture. These synthetic tests are development diagnostics, not the PRD acceptance corpus.

For release qualification, record model ID and revision; source and conversion licenses; runtime/compiler/OS revisions; tokenizer and processor hashes; quantization scheme and group size; actual download bytes; disk/compiled-cache bytes; cold and warm timing; peak process footprint; memory pressure and swap; image/context/output token budgets; task successes and errors; and cancellation behavior.

Use a 16 GB M2 Air as the release baseline, then verify representative M3-M5 machines. Hold browser/app workload and corpus fixed. Report every failed case and unsupported capability. The PRD defines the evaluation sets and release gates. Select the smallest, fastest configuration **among those that meet the required task quality**, rather than declaring a winner from unrelated model leaderboards.
