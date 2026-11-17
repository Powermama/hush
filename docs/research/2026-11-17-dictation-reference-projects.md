# Dictation reference projects

Reviewed 16-17 November 2026, from each project's own source at the pinned commit below. Every claim links to the file it comes from; "Not found" means the feature was not found in the source read, not that it is proven absent. Measured numbers are the project's own unless the row says "measured by hush".

This is the open-source half of the research behind the Live Write PRD. The study of the closed Wispr Flow client is kept out of this public repository; its findings live in the private PRD (section 3.5). hush takes ideas and measurements from these projects, not code, unless a licence allows it and the file says so (for example `FillerWords.json` credits Handy).

## Projects

| Project | Commit | Licence | Stack | Where the text work runs |
| --- | --- | --- | --- | --- |
| [phonon](https://github.com/Infatoshi/phonon/tree/ae03e170a3e033faee307fae3b37151f32d32683) and [phonon-research](https://github.com/Infatoshi/phonon-research/tree/29659961784c88810bf981c04341c319c9f29b75) | ae03e17, 2965996 | GPL-3.0 (refiner weights: LFM 1.0) | Swift bar, Rust engine, Python sidecars | On the Mac: Parakeet TDT v2 and a fine-tuned 1.7B refiner |
| [Flowstate](https://github.com/rdewsnap/Flowstate/tree/e84248d2b9d5932406fca688e7fa342cc325d722) | e84248d | AGPL-3.0 | Swift app, Rust core | On the Mac (llama-server) or hosted |
| [VoiceInk](https://github.com/Beingpax/VoiceInk/tree/b5d1be9a7c7377dd059f37bb3e0f791b802d4001) | b5d1be9 | GPL-3.0 | Swift | Speech on the Mac; enhancement mostly through cloud models |
| [FluidVoice](https://github.com/altic-dev/FluidVoice/tree/ff148610e7309e167e254c95a42d1c4031901c1b) | ff14861 | GPL-3.0 | Swift on FluidAudio | On the Mac: own "Fluid 1.1" clean-up models |
| [FreeFlow](https://github.com/zachlatta/freeflow/tree/37786464bb2422c58313d7456fe7191d115d0d18) | 3778646 | MIT | Swift | Hosted models (Groq, OpenAI-compatible) |
| [Handy](https://github.com/cjpais/Handy/tree/aca8985190c3ad7f361d8a80cb30f179513ed690) | aca8985 | MIT | Tauri (Rust) | On the Mac; optional clean-up prompt |
| [OpenWhispr](https://github.com/OpenWhispr/openwhispr/tree/ad7424068824ceae479aa8882140ed1f7a15b5a1) | ad74240 | MIT | Electron | Local or cloud, user's choice |
| [Amical](https://github.com/amicalhq/amical/tree/02c2b161b58cecc7ce5fce129b730524e1a0b138) | 02c2b16 | MIT | Electron, Swift helper | Local (Ollama) or cloud |
| [FluidAudio](https://github.com/FluidInference/FluidAudio/tree/16780f04d2ece24f67d0fc00efccd0296491c1a8) | 16780f0 | Apache-2.0 (models vary) | Swift library | On the Mac; hush's Parakeet engine |

## How each feature works

| Feature | phonon | Flowstate | VoiceInk | FluidVoice | FreeFlow | Handy | OpenWhispr | Amical |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Reads context | App and site category; screen text (350 words) and text before the cursor (40 words) | App style (casual, prose, code) | Selected text, clipboard, OCR of the window | Text before the cursor (2,000 chars), screen text by Accessibility, OCR fallback | Model summary of app, window and screenshot | Nothing | Screenshot, only when the request points at the screen | Text before and after the cursor, app type |
| Removes fillers | Fine-tuned refiner | Rule filter, then a fine-tuned model | Prompted model | Own model | Hosted model | Word list | Prompted model | Prompted model |
| Write or dictate | Mode from app category; "prompt" mode never answers | Clean-up only | Modes by hotkey, app or site rule, or trigger word | Separate hotkeys per mode | Clean-up only | Clean-up only | Agent addressed by name, or its own hotkey | Clean-up only |
| Works while speaking | ASR rounds every 0.4 s; refiner drafts in the background | Transcribes at pauses while the key is held | Not found | Live preview | Not found | Not found | Not found | A live transcription session (not analysed) |
| Safety check | Word-count guard; deletion check | Guardrail; fallback to the rule filter | Not found | Not found | Not found | Not found | Prompt rules only | Prompt rules only |
| Learns from the user | Edits after paste; on-device LoRA "Train Now" | Vocabulary from one correction | Word replacements from edits after paste | Dictionary corrections from edits | Vocabulary button | Not found | Not found | Not found |

### phonon

The most complete design, and the closest to Live Write.

- **Two models, both local:** Parakeet TDT 0.6B v2 on phonon's own Metal kernels, and the "Phonon refiner 1.7B", fine-tuned from LiquidAI LFM3-1.7B. Download is about 4.9 GB. Key-up to pasted text is about 65 ms on an M4 Max ([README](https://github.com/Infatoshi/phonon/blob/ae03e170a3e033faee307fae3b37151f32d32683/README.md)).
- **One written target for every component:** "the text the speaker intended to type". Fillers, stutters, false starts and tag questions go; only the final version of a self-correction stays; nothing is invented or dropped ([SPEC "Intended text and writing modes"](https://github.com/Infatoshi/phonon/blob/ae03e170a3e033faee307fae3b37151f32d32683/SPEC.md#intended-text-and-writing-modes-the-public-refiner-since-10)).
- **Writing modes from the target app:**
  - casual in chat, formal in email, minimal in documents;
  - prompt in AI apps and terminals, where the request is never answered or extended.
  - The category table follows Wispr Flow 1.6's app lists, regrouped into six categories. A website host decides before a bundle id ([app_context.rs](https://github.com/Infatoshi/phonon/blob/ae03e170a3e033faee307fae3b37151f32d32683/crates/phonon-core/src/app_context.rs)).
- **Refiner prompt:**
  - System turn: the instruction, the mode line, the vocabulary line, then "On screen" (the first 350 words of screen text) and "Before cursor" (the last 40 words).
  - Decoding: greedy, thinking off, at most 1.5 times the transcript's tokens plus 32.
  - A "join rule" lower-cases the transcript when the text before the cursor ends mid-sentence.
  - Every platform checks its prompt against shared fixtures byte for byte.
- **Streaming:**
  - Every 0.4 s chunk starts a speculative ASR round over the whole recording. At key release only the last stretch is transcribed.
  - Measured against whole-file ASR on 1,351 public clips: +0.0009 WER (95% CI -0.0006 to +0.0023).
  - Parakeet's own chunked streaming differed from batch ASR by 0.46 WER, so phonon does not use it.
  - The refiner drafts in the background, and the final output is verified token by token against the final prompt ([SPEC "Streaming refine"](https://github.com/Infatoshi/phonon/blob/ae03e170a3e033faee307fae3b37151f32d32683/SPEC.md#streaming-refine-settingsjson-stream_refine-default-on-with-16-gb-of-memory-or-more)).
- **Context privacy:**
  - A denylist the user edits, with Signal and Discord on it by default.
  - An always-private list of password managers and macOS authorization prompts ([AppContextCapture.swift](https://github.com/Infatoshi/phonon/blob/ae03e170a3e033faee307fae3b37151f32d32683/macos/Sources/AppContextCapture.swift)).
- **Learning from edits:**
  - After paste, phonon pins the text field, keeps anchors before and after the insertion, and re-reads the field.
  - The user's version is whatever sits between the anchors. The mechanism follows Wispr Flow 1.6's Swift helper ([EditLearning.swift](https://github.com/Infatoshi/phonon/blob/ae03e170a3e033faee307fae3b37151f32d32683/macos/Sources/EditLearning.swift)).
  - "Train Now" builds a LoRA adapter from these pairs, always from the shipped refiner, never stacked.
  - The adapter has to pass a gate on held-out user and public sets before use ([SPEC "On-device fine-tuning"](https://github.com/Infatoshi/phonon/blob/ae03e170a3e033faee307fae3b37151f32d32683/SPEC.md#on-device-fine-tuning-train-now)).
- **Training data:**
  - 76,960 transcripts of public audio and synthetic dictations, each rewritten by DeepSeek following the spec, in four modes.
  - The research repository adds acoustic synthetic pairs: sentences around vocabulary terms, spoken by 9 Kokoro voices and recognised by Parakeet, so the raw side carries real ASR errors. Text-only synthetic corruption never beat the raw transcript ([phonon-research ml/SPEC.md](https://github.com/Infatoshi/phonon-research/blob/29659961784c88810bf981c04341c319c9f29b75/ml/SPEC.md)).
- **Ship gate (phonon-bench):** frozen sets for real dictation, vocabulary terms and numerics. Metrics: fair WER, a damage rate (rows worse than the raw transcript), error classes per 1,000 words, and latency.
- **Weakness for hush:** English only, tuned for developers dictating to coding agents, and the speed rests on custom Metal kernels.

### Flowstate

- **Layers:**
  1. A rule filter that is safe on its own ([filter.rs](https://github.com/rdewsnap/Flowstate/blob/e84248d2b9d5932406fca688e7fa342cc325d722/crates/fnspeak-core/src/filter.rs)).
  2. A skip check that keeps already-clean dictations away from the model ([skip.rs](https://github.com/rdewsnap/Flowstate/blob/e84248d2b9d5932406fca688e7fa342cc325d722/crates/fnspeak-core/src/cleanup/skip.rs)).
  3. A language model.
  4. A guardrail that rejects empty, runaway, answering or placeholder output and falls back to the rule filter's text ([cleanup/mod.rs](https://github.com/rdewsnap/Flowstate/blob/e84248d2b9d5932406fca688e7fa342cc325d722/crates/fnspeak-core/src/cleanup/mod.rs)).
- **Style:** casual, prose or code, from the app ([context.rs](https://github.com/rdewsnap/Flowstate/blob/e84248d2b9d5932406fca688e7fa342cc325d722/crates/fnspeak-core/src/context.rs)).
- **Fine-tunes** ([training/RESULTS.md](https://github.com/rdewsnap/Flowstate/blob/e84248d2b9d5932406fca688e7fa342cc325d722/training/RESULTS.md)):
  - Training: Qwen3 0.6B and 1.7B with mlx-lm LoRA (rank 16) on 25,697 pairs. Sources: corrupted WikiText, oasst1 and Dolly, SottoASR, Aawaaz, Disfl-QA, plus pairs from the 4B model.
  - 0.6B: 5.2% WER at 170 ms.
  - 1.7B: 4.1% WER at 315 ms.
  - Prompted Qwen3-4B: 14.8% at 652 ms.
  - Caveat: the validation set follows the training conventions, which favours the fine-tunes.
- **Speech step:** Whisper large-v3-turbo with a trimmed encoder window (`audio_ctx` 1024 under 20 s) cut speech time from 567 to 360 ms with no accuracy loss on its clips.
- **Weakness for hush:** the skip check and the soft-filler list are English word lists.

### VoiceInk

- **Context:**
  - the selected text, the clipboard, and text from an OCR of the focused window (ScreenCaptureKit plus Vision, [ScreenCaptureService.swift](https://github.com/Beingpax/VoiceInk/blob/b5d1be9a7c7377dd059f37bb3e0f791b802d4001/VoiceInk/Infrastructure/SystemIntegration/ScreenCapture/ScreenCaptureService.swift));
  - each is a setting, and each goes into a tagged block of the prompt ([AIEnhancementService.swift](https://github.com/Beingpax/VoiceInk/blob/b5d1be9a7c7377dd059f37bb3e0f791b802d4001/VoiceInk/Features/Enhancement/Workflows/AIEnhancementService.swift)).
- **Prompt templates:** one system template around every mode ([PromptTemplates.swift](https://github.com/Beingpax/VoiceInk/blob/b5d1be9a7c7377dd059f37bb3e0f791b802d4001/VoiceInk/Features/Enhancement/Templates/PromptTemplates.swift)).
  - "Rewrite" treats selected text as the source and the dictation as the instruction.
  - "Assistant" answers the request.
- **Modes:** switched by hotkey, by app or website rules, or by a spoken trigger word that is stripped from the text ([ModeTriggerWordDetectionService.swift](https://github.com/Beingpax/VoiceInk/blob/b5d1be9a7c7377dd059f37bb3e0f791b802d4001/VoiceInk/Features/Modes/Models/ModeTriggerWordDetectionService.swift)).
- **Auto-learn:** after paste it watches the field, diffs the final text against what was pasted, and proposes word replacements for review, locally or by AI ([AutoLearn/](https://github.com/Beingpax/VoiceInk/tree/b5d1be9a7c7377dd059f37bb3e0f791b802d4001/VoiceInk/Features/Dictionary/AutoLearn)).
- **Weakness for hush:** quality rests on cloud models, and the user picks the mode.

### FluidVoice

- **Context capture** ([DictationContextCapture.swift](https://github.com/altic-dev/FluidVoice/blob/ff148610e7309e167e254c95a42d1c4031901c1b/Sources/Fluid/Services/DictationContextCapture.swift)):
  - up to 2,000 characters before the cursor, and screen text through Accessibility within a 0.5 s budget;
  - Vision OCR only when Accessibility yields fewer than 25 words;
  - password managers skipped.
- **Own clean-up models:** "Fluid 1.1 Ripple" (about 600 MB) and "Splash" (about 750 MB), research previews ([README](https://github.com/altic-dev/FluidVoice/blob/ff148610e7309e167e254c95a42d1c4031901c1b/README.md)). They take the raw context.
- **Prompt-prefix cache:** the fixed start of the prompt can stay in the model's KV cache between dictations (`usesStablePromptPrefixKVCache`, [PrivateAIIntegrationService.swift](https://github.com/altic-dev/FluidVoice/blob/ff148610e7309e167e254c95a42d1c4031901c1b/Sources/Fluid/Services/PrivateAIIntegrationService.swift)).
- **Modes:** dictate, prompt, edit and command, each on its own hotkey.
- **Weakness for hush:** no automatic decision between writing and dictation; the models are research previews.

### FreeFlow

- **Context synthesis:** a first model call turns app and window metadata, plus an optional screenshot, into two sentences describing what the user is doing and the likely writing intent ([AppContextService.swift](https://github.com/zachlatta/freeflow/blob/37786464bb2422c58313d7456fe7191d115d0d18/Sources/AppContextService.swift)). The clean-up then uses that summary instead of an app table.
- **Weakness for hush:** sends a screenshot to a hosted model, which is not acceptable for an on-device product.

### Handy

- **Hesitation removal in two tiers:** sounds that are a word in no language are always removed; sounds that are words somewhere only with the language known ([text.rs](https://github.com/cjpais/Handy/blob/aca8985190c3ad7f361d8a80cb30f179513ed690/src-tauri/src/audio_toolkit/text.rs)). It also collapses a word said three or more times in a row.
- **Recording safety:** each recording is written to disk as a temporary file and renamed when complete, so a crash never loses or half-writes one ([transcription_jobs.rs](https://github.com/cjpais/Handy/blob/aca8985190c3ad7f361d8a80cb30f179513ed690/src-tauri/src/managers/transcription_jobs.rs)).
- **Optional clean-up prompt:** it forbids following instructions in the transcript ([settings.rs](https://github.com/cjpais/Handy/blob/aca8985190c3ad7f361d8a80cb30f179513ed690/src-tauri/src/settings.rs)).
- **Weakness for hush:** no context and no writing.

### OpenWhispr

- **Two prompts:** "cleanup" never acts on the speech; the agent prompt executes a command ([prompts.json](https://github.com/OpenWhispr/openwhispr/blob/ad7424068824ceae479aa8882140ed1f7a15b5a1/src/locales/en/prompts.json)).
- **Triggering the agent:**
  - by addressing it by name, with fuzzy matching and greetings in 9 languages ([agentDetection.ts](https://github.com/OpenWhispr/openwhispr/blob/ad7424068824ceae479aa8882140ed1f7a15b5a1/src/config/agentDetection.ts));
  - or with its own hotkey, which always takes the agent path ([dictationRouting.js](https://github.com/OpenWhispr/openwhispr/blob/ad7424068824ceae479aa8882140ed1f7a15b5a1/src/helpers/dictationRouting.js)).
- **Screenshots:** go to the agent only when the request refers to the screen. Text in the screenshot is never treated as an instruction.
- **Weakness for hush:** no automatic decision; the shipped build carries cloud providers and connectors beside the local models.

### Amical

- **Formatter prompt** ([formatter-prompt.ts](https://github.com/amicalhq/amical/blob/02c2b161b58cecc7ce5fce129b730524e1a0b138/apps/desktop/src/pipeline/providers/formatting/formatter-prompt.ts)):
  - tuned by evaluation ("structured-v2");
  - rules and few-shot examples per app type: email, chat, notes;
  - the text before and after the cursor, for spacing and continuity.
- **App types:** come from a bundle-id catalog ([app-catalog.ts](https://github.com/amicalhq/amical/blob/02c2b161b58cecc7ce5fce129b730524e1a0b138/apps/desktop/src/shared/app-catalog.ts)).
- **Context into speech:** the text before the cursor also goes into Whisper's initial prompt ([whisper-provider.ts](https://github.com/amicalhq/amical/blob/02c2b161b58cecc7ce5fce129b730524e1a0b138/apps/desktop/src/pipeline/providers/transcription/whisper-provider.ts)).
- **Weakness for hush:** formats only; it never writes on request.

### FluidAudio

hush's Parakeet engine.

- **Token revisions:** a stream of raw token edits during sliding-window transcription. Only the stable prefix is final ([TokenRevisions.md](https://github.com/FluidInference/FluidAudio/blob/16780f04d2ece24f67d0fc00efccd0296491c1a8/Documentation/ASR/TokenRevisions.md)). Added after 0.18.0, which hush pins.
- **Vocabulary boosting** for the user's terms ([CustomVocabulary.md](https://github.com/FluidInference/FluidAudio/blob/16780f04d2ece24f67d0fc00efccd0296491c1a8/Documentation/ASR/CustomVocabulary.md)).
- **Text normalisation:** inverse text normalisation in 7 languages through text-processing-rs ([PostProcessing.md](https://github.com/FluidInference/FluidAudio/blob/16780f04d2ece24f67d0fc00efccd0296491c1a8/Documentation/ASR/PostProcessing.md)).
- **Bark 3.0 Clean:** a Parakeet v3 post-training that drops fillers, false starts and repeated words. English only. The original weights are licensed CC-BY-NC-4.0 ([Bark3.md](https://github.com/FluidInference/FluidAudio/blob/16780f04d2ece24f67d0fc00efccd0296491c1a8/Documentation/ASR/Bark3.md)).

## Published models checked

| Model | What it does | Languages | Licence | Note |
| --- | --- | --- | --- | --- |
| [Superwhisper S1-mini](https://huggingface.co/superwhisper/s1-mini) | Qwen3-0.6B fine-tune: fillers, self-corrections, punctuation, numbers; 94.8% token accuracy | English | Apache-2.0 plus a naming clause | Rewrites, so it can change words |
| [stillerman fdt taggers](https://huggingface.co/stillerman/fdt-disfluency-distilbert-66m-v5) | Delete-only tagger, 4M to 66M parameters, 10-50 ms in a browser, DELETE-F1 0.99 | English | Apache-2.0, but trained partly on CC BY-NC-SA data | Research use only, by its card |
| [Underdog Bark 3.0 Clean](https://huggingface.co/ConwayResearch/Underdog-Bark-3.0-Clean) | Speech model with clean output | English | CC-BY-NC-4.0 | Not shippable without permission |
| [Phonon refiner 1.7B](https://huggingface.co/Infatoshi/phonon-refiner-1.7b) | Clean-up and term correction | English | LFM 1.0 | Its licence needs review |

No released multilingual clean-up model was found. [Mind the Pause (ACL 2026)](https://aclanthology.org/2026.acl-long.2137.pdf) describes a tagger plus a language model for Hindi, Marathi and Bengali, without a released checkpoint.

## Measured by hush

| Benchmark | Where | First result |
| --- | --- | --- |
| Hesitation floor | `macos/Hush/HushTests/FillerWordsBenchmark.swift` | 27/27 required cases, no real word removed, 16 µs median |
| Fillers per speech engine | `macos/Hush/HushTests/SpeechFillerBenchmark.swift` | German fillers dropped by every engine. English: 12 of 14 left with Parakeet Ultra and Whisper large-v3 turbo, 0 with Bark 3.0 Clean |
| Personas on real models | `macos/Hush/HushTests/PersonaLiveTests.swift` | Qwen 3.5 4B 33/36, Apple Intelligence 28/36 |

## What hush takes from this

- **One written target** for what "finished text" means, shared by prompts, training data and tests (phonon).
- **Writing mode from the target app,** as data with a per-app override, and "prompt" mode for AI apps and terminals (phonon, Flowstate, Amical).
- **Context through Accessibility first:**
  - Read the text before the cursor, the selection and the screen within a fixed time budget, with OCR only as a fallback (FluidVoice, phonon).
  - Password managers and authorization prompts are never read (phonon, FluidVoice).
- **Work while the user speaks:** ASR rounds every 0.4 s, and background drafts verified against the final prompt (phonon).
- **Deterministic guard around every model output,** with a fallback to safe text (Flowstate, phonon).
- **Learning from the user's edits after paste,** with anchors around the inserted text and proposals the user reviews (phonon, VoiceInk).
- **A stable prompt start kept in the model's cache** (FluidVoice).
- **Recordings written to disk while recording** (Handy).
- **Small fine-tuned models trained on synthetic pairs,** gated by a frozen benchmark (phonon, Flowstate).
