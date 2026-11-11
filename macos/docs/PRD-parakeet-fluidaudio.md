# PRD - Parakeet Transcription via FluidAudio

**Status:** Phases 1-2 implemented on `feat/parakeet-fluidaudio`; phase 3 waits for the real-voice benchmark  
**Date:** 2026-10-31  
**Platform:** macOS 15+  
**New dependency:** [FluidAudio](https://github.com/FluidInference/FluidAudio) `0.18.x` (Swift Package, Apache-2.0)  
**Product promise:** Hush writes what you said more accurately and faster, without sending audio anywhere.

## 1. Executive decision

Add FluidAudio as a second on-device speech engine next to WhisperKit, and offer NVIDIA Parakeet models through it. Parakeet Ultra becomes the recommended model for every language it supports.

| Decision | Choice |
|---|---|
| Integration | Swift Package Manager, the same way `argmax-oss-swift` (WhisperKit) is integrated today |
| Main model | Parakeet Ultra (`AsrModelVersion.ultra`, 603 MB, 25 European languages, Sep 2026) |
| Compact model | Parakeet Redux (`.redux`, 210 MB, same 25 languages, Sep 2026) |
| Older Parakeet generations | Not offered. Only the newest generation is listed (v3, v2 and the 110M model are left out). |
| Offline first launch | Unchanged: the bundled Whisper model (`base` in the public build, `large-v3-v20240930_547MB` in the internal build, see `ModelInfo.defaultModelID`) is the model until the user downloads Parakeet |
| Fallback | WhisperKit stays for languages Parakeet does not cover (zh, ja, ko, ar, hi, tr in today's picker) |
| Seam | A new `FluidAudioTranscriber` behind the existing `Transcriber` protocol. No other part of the dictation pipeline learns which engine runs |

Not in scope for v1: streaming partial text, Parakeet custom vocabulary (CTC boosting), FluidAudio's TTS and speaker diarization, bundling Parakeet inside the `.app`.

Interaction with PRD-personal-vocabulary: its recognition-hint layer uses WhisperKit `promptTokens`. With a Parakeet model active, only its deterministic correction layer applies until Parakeet CTC boosting lands (phase 4).

## 2. Why

### 2.1 Evidence

The only same-device comparison that includes the model Hush ships today (Argmax, earnings22 subset, M4 Mac mini, June 2025):

| Engine | WER | Speed |
|---|---|---|
| WhisperKit whisper-base.en (closest to Hush's bundled multilingual `base`) | 15.2% | 111x realtime |
| Apple SpeechTranscriber | 14.0% | 70x |
| WhisperKit whisper-small.en | 12.8% | 35x |
| Parakeet v2 | 11.7% | 359x |

Parakeet Ultra versus v3, as published by FluidAudio (same machine, full test sets):

| Set | v3 | Ultra |
|---|---|---|
| LibriSpeech test-clean | 2.27% | 2.13% |
| LibriSpeech test-other | 4.12% | 3.81% |
| FLEURS, 24-language mean | 14.81% | 11.67% |
| Speed on the Neural Engine | 128.6x | 126.7x |

For push-to-talk, latency per short clip matters more than speed on long audio. A public test with 50 short LibriSpeech utterances on an M4 Air measured Parakeet v3 at 88 ms median latency and 0.13 s cold start.

The Ultra numbers are self-reported by the publishers. Section 9 makes our own benchmark a release gate.

### 2.2 Why FluidAudio and not an alternative

| Option | Verdict |
|---|---|
| **FluidAudio** | Chosen. Apache-2.0 Swift package, CoreML on the Neural Engine, no third-party package dependencies, ships Ultra, Redux and v3. Used by VoiceInk, Spokenly and 40+ other Mac apps. |
| `argmax-oss-swift` (WhisperKit, already a dependency) | No Parakeet support in the open-source package. |
| Argmax Pro SDK | Has Parakeet and custom vocabulary, but is paid per device and closed source. |
| `mlx-audio-swift` | Runs on the GPU, not the Neural Engine. Early stage, no published Mac benchmarks. |
| Apple SpeechAnalyzer | macOS 26 only, 10 languages (no ru/uk), custom vocabulary only in DictationTranscriber, no model control. |

### 2.3 Trade-off we accept

Parakeet is not smaller than whisper-base. Ultra is ~630 MB against 143 MB for the bundled whisper-base folder. Redux (~220 MB) is the answer for users who care about disk space. Ultra's encoder is a single ~595 MB file, so it cannot be bundled in the public GitHub build (100 MB per-file limit) and is download-only.

## 3. User experience

### 3.1 New user

1. The app launches with the bundled Whisper model and works offline immediately (unchanged). Onboarding is unchanged: its contract says first run never requires a download.
2. Parakeet is offered in Settings > Transcription. Recommending it in onboarding is phase 3, after the benchmark gate.

### 3.2 Model selection flow (implemented)

The full contract is `docs/user-journeys/transcription-models.md`. In short:

- **Transcription page:** a hero card for the active model (engine, name, size, languages, release month, status and preparation progress), then one card per engine (Parakeet, Whisper) with model counts and an Active badge.
- **Engine page:** clicking an engine opens its models with a back button. Each row shows name, size, language coverage and release month, a badge (Active, Downloaded, Built in) and one state button: Download, Cancel, Use or Retry. Whisper rows are grouped into Fast, Balanced and Most accurate, newest first, with an All / Multilingual / English only filter.
- **Download is separate from activation.** A download runs in `ModelDownloadService` with progress and Cancel, and never changes the active model, so dictation keeps working. A finished download shows Use. One download runs at a time, and a download is refused up front when free space is below the model size plus 15%.
- Nothing changes automatically for existing users. The "Recommended" label is phase 3.

### 3.3 Language rules

Parakeet v3-family models support these 25 languages: bg, hr, cs, da, nl, en, et, fi, fr, de, el, hu, it, lv, lt, mt, pl, pt, ro, sk, sl, es, sv, ru, uk.

| Situation | Behaviour |
|---|---|
| Language is "Auto-detect" and a Parakeet model is selected | Parakeet detects the language itself. Speech outside its 25 languages produces poor text; the language picker says so in its help text. |
| Language is one Parakeet supports | Hush passes it as a language hint to FluidAudio (script-aware token filtering). |
| User picks a language Parakeet does not support (zh, ja, ko, ar, hi, tr) while a Parakeet model is active | The language row shows "Not supported by Parakeet" and an inline action "Switch to Whisper". Hush does not silently swap engines. |
| User picks a Parakeet model while such a language is set | The model row is shown as unavailable for that language, with the reason. |

The explicit rule above keeps one loaded model in memory at a time. Silent per-dictation switching would load two models and is left for later.

### 3.4 Settings that change meaning

- **Transcription quality (Fast / Balanced / Best)** maps to Whisper's temperature fallback. It has no Parakeet equivalent. With a Parakeet model selected, the control is disabled with the note "Parakeet always runs at full quality."
- **Model storage**: Parakeet models appear in the same list with size, Reveal in Finder and Delete actions as Whisper models.

### 3.5 Attribution

Parakeet weights are CC-BY-4.0. Settings > About lists "Speech recognition: NVIDIA Parakeet (CC-BY-4.0), Parakeet Ultra and Redux by Moondream, run with FluidAudio by FluidInference (Apache-2.0)" with links.

## 4. Architecture

### 4.1 Current state (verified in code, 2026-10-31)

- `Transcriber` protocol (`Hush/Hush/Transcription/Transcriber.swift`): `prepare(modelID:progress:)`, `transcribe(samples:language:fallbackCount:)`, `unload()`. Input is 16 kHz mono Float32.
- `TranscriberFactory.make()` returns `WhisperKitTranscriber` (or `MockTranscriber`).
- `DictationCoordinator.prepareModelInBackground()` creates a fresh transcriber per model switch, cancels obsolete preparations by generation, and calls `prepare`.
- `ModelInfo` describes only Whisper variants. `ModelCatalogService` builds the list from the `argmaxinc/whisperkit-coreml` Hugging Face tree.
- `ModelManager` knows WhisperKit's on-disk layout only. `AIModelStorage.root` is `~/Library/Application Support/Hush/Models/`.

### 4.2 Target design

```text
DictationCoordinator
   └─ TranscriberFactory.make(for: modelID)
         ├─ engine == .whisperKit  → WhisperKitTranscriber   (unchanged)
         └─ engine == .fluidAudio  → FluidAudioTranscriber   (new)
```

**`SpeechEngine`** (new enum): `.whisperKit`, `.fluidAudio`.

**`ModelInfo`** gains:
- `engine: SpeechEngine` (decoded with a `.whisperKit` default so the existing `modelCatalog.v1` cache stays readable).
- `supportedLanguages: Set<String>?` (`nil` = all of Whisper's languages).

**Model IDs.** Parakeet IDs use a `parakeet-` prefix that can never collide with a WhisperKit variant name:

| Hush model ID | `AsrModelVersion` | HF repo | Display name |
|---|---|---|---|
| `parakeet-ultra` | `.ultra` | `FluidInference/parakeet-ultra-coreml` | Parakeet Ultra |
| `parakeet-redux` | `.redux` | `FluidInference/parakeet-redux-coreml` | Parakeet Redux |

`Settings.modelID` stays a plain string. The engine is derived from the ID, so no settings migration is needed.

**Catalog.** Parakeet entries are a curated static list (`ModelInfo.fluidAudioEntries`), not scraped from Hugging Face. FluidAudio's `AsrModelVersion` enum is the source of truth for what the pinned package can load, so the list changes only when we bump the package. Sizes are fetched once from the HF tree API for display, the same way as Whisper sizes, with hard-coded fallbacks.

**`TranscriberFactory`** becomes `make(for modelID: String) -> Transcriber`. `DictationCoordinator` already constructs a fresh transcriber per preparation, so it passes the ID through. The `makeTranscriber` injection point used by tests takes the ID too.

### 4.3 `FluidAudioTranscriber`

```swift
nonisolated final class FluidAudioTranscriber: Transcriber, @unchecked Sendable {
    func prepare(modelID: String, progress: ...) async throws
    func transcribe(samples: [Float], language: String, fallbackCount: Int) async throws -> String?
    func unload() async
}
```

**prepare**
1. Map `modelID` to `AsrModelVersion`. Unknown ID throws `TranscriberError.backendUnavailable`.
2. If the model is not on disk, `AsrModels.download(to:version:progressHandler:)` into a folder per model under `AIModelStorage.fluidAudioRoot`, mapping progress to 0...0.95 as `WhisperKitTranscriber` does. `download` and `load` derive a parent directory from the path they get (`deletingLastPathComponent()`), so the phase 1 spike confirms the exact `to:` / `from:` semantics before the folder layout is fixed.
3. `AsrModels.load(from:version:)` with FluidAudio's default configuration (preprocessor on CPU, other components on `.cpuAndNeuralEngine`).
4. Create an `AsrManager(config: .default)` and call `loadModels(_:)` with the models.
5. Warm up: transcribe 1 s of silence so CoreML compiles its graph before the first hotkey press. Log load and warm-up times like the WhisperKit path does.
6. Report progress 1.0.

**transcribe**
1. Empty samples throw `TranscriberError.empty` (same as today).
2. Clips shorter than FluidAudio's minimum (0.3 s, `ASRConstants.minimumAudioDurationSeconds`) return `nil` ("no speech") instead of surfacing `ASRError.invalidAudioData`.
3. Clips shorter than 1.0 s are padded with trailing silence to 1.0 s. This mitigates the known Parakeet failure of empty output on very short utterances. Section 9 verifies whether padding is needed and whether 1.0 s is the right length.
4. Map `language` to `FluidAudio.Language` when it is one of the 25, else pass `nil`.
5. Call `transcribe(_ samples:decoderState:language:)` with a **fresh `TdtDecoderState` for every dictation** (`TdtDecoderState.make()`), so decoder state from the previous push-to-talk clip never carries into the next one. In 0.18 every `AsrManager.transcribe` overload takes the decoder state as `inout`.
6. `fallbackCount` is ignored (documented on the protocol).
7. Trim the result and return `nil` when empty, as today.
8. Log elapsed time and RTF in the same format as `WhisperKitTranscriber` so logs stay comparable.

**Concurrency.** Follow the WhisperKit class: opt out of MainActor isolation, guard the loaded manager with a private serial queue, support cancellation between steps. `DictationCoordinator`'s generation guard already protects against overlapping preparations.

### 4.4 Storage

- New `AIModelStorage.fluidAudioRoot` = `<root>/fluidaudio/`. Never FluidAudio's default cache directory, matching the rule that third-party SDKs must not scatter model files.
- `ModelManager` gains engine-aware `isInCache`, `cacheURL`, `diskUsageBytes`, `delete` and `reveal`. For FluidAudio a model is complete when FluidAudio's own existence check `AsrModels.modelsExist(at:version:)` (present in 0.18.0) passes, never on folder existence alone. This repeats the lesson already documented in `ModelManager.isInCache`.
- `availableIDs()` also scans the FluidAudio root.

### 4.5 Package integration (native Swift Package, Xcode-managed)

**Principle:** FluidAudio enters Hush exactly like WhisperKit (`argmax-oss-swift`), `mlx-swift-lm` and Sparkle: a remote Swift Package managed by Xcode inside `Hush.xcodeproj`. No CocoaPods, no vendored source, no git submodule, no prebuilt framework copied into the repo, no extra build scripts. Models are fetched at runtime through FluidAudio's own API, not by custom download code.

**Adding it in Xcode**
1. Open `macos/Hush/Hush.xcodeproj`, then File > Add Package Dependencies.
2. URL `https://github.com/FluidInference/FluidAudio.git`, Dependency Rule **Up to Next Minor Version** from `0.18.0`. The project releases weekly and is pre-1.0, so a minor bump can break the API. Bumps are deliberate PRs.
3. Add only the **FluidAudio** library product to the **Hush** app target. Do not add the `fluidaudiocli` executable product.
4. Commit the new `XCRemoteSwiftPackageReference "FluidAudio"`, `XCSwiftPackageProductDependency` and framework build-file entries in `project.pbxproj`. `Package.resolved` is gitignored in this repo, so the version rule in the project file is the pin.

**What the package brings**
- No transitive Swift package dependencies, so `Package.resolved` gains exactly one entry and cannot clash with the versions WhisperKit or mlx-swift pin.
- One binary target, `NemoTextProcessing.xcframework` (text normalization), resolved by SwiftPM from a checksummed GitHub release. Verify that it embeds, signs and notarizes cleanly in the Sparkle release pipeline before merging.
- Minimum platform macOS 14, below Hush's macOS 15.

**Building**
- The verified CLI build stays the same: `xcodebuild -project macos/Hush/Hush.xcodeproj -scheme Hush -configuration Debug -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO build`. FluidAudio ships no package plugins, so it adds no new trust prompt.
- CI resolves packages with `xcodebuild -resolvePackageDependencies` like today.

**Trimming unused parts**
FluidAudio's Swift 6.2 package manifest exposes traits (`TTS`, `Diarizer`, `NemoTextProcessing`) to drop unused subsystems. Traits are set on the consuming side. Phase 1 checks whether Xcode's project-level package references can set them. If they cannot, v1 accepts the extra compiled code rather than adding a wrapper package. Do not create a local wrapper `Package.swift` only for this.

**Code guard**
`TranscriberFactory` uses `#if canImport(FluidAudio)`, mirroring the existing `#if canImport(WhisperKit)` guard, so the project still builds if the package is removed.

## 5. Functional requirements

| ID | Requirement |
|---|---|
| FR-1 | Users can download, select and delete Parakeet Ultra and Redux, and reveal their folder, from Settings > Transcription > Parakeet. |
| FR-2 | Selecting a Parakeet model prepares it in the background with visible progress. Dictation on the previous model keeps working until the new one is ready. |
| FR-3 | The first dictation after a Parakeet model shows "ready" has no compile delay (warm-up done in `prepare`). |
| FR-4 | Push-to-talk clips from 0.3 s to 120 s transcribe correctly. Clips under 0.3 s are treated as "no speech" with the existing UI. |
| FR-5 | The language rules in section 3.3 are enforced in Settings and onboarding. |
| FR-6 | The Transcription quality control is disabled with an explanation when a Parakeet model is selected. |
| FR-7 | All Parakeet files live under `~/Library/Application Support/Hush/Models/fluidaudio/`. Nothing is written to `~/.cache`, Documents or FluidAudio's default directory. |
| FR-8 | Activity history records the Parakeet model's display name exactly as it does for Whisper. |
| FR-9 | Post-processing, personas and refinement run unchanged on Parakeet output. |
| FR-10 | About shows the CC-BY-4.0 attribution from section 3.5. |
| FR-11 | The bundled Whisper model (public: `base`, internal: `large-v3` compressed) remains the offline first-launch model. |

## 6. Non-functional targets

Measured on an M1 MacBook Air (the slowest Mac we support well) and an M4. These are targets to confirm in the benchmark (section 9), not promises yet.

| Metric | Target |
|---|---|
| Hotkey release to text inserted, 5 s clip, Parakeet Ultra, warm | p50 under 250 ms, p95 under 500 ms |
| WER on the Hush test corpus (section 9.2), English and German | At least 25% relative improvement over `base` (public build); no regression against `large-v3` compressed (internal build) |
| Empty outputs on non-silent clips of 0.5-1.0 s | 0 in the corpus |
| Peak memory during dictation | Not more than whisper-large-v3 today |
| `prepare` on an already downloaded model (cold app launch) | Under 3 s on M1 |
| App binary size increase from the package | Under 15 MB |

## 7. Edge cases and error handling

| Case | Handling |
|---|---|
| Download interrupted or app quit mid-download | The existence check fails and the row shows Download again. A retry resumes or redownloads. Never load a partial folder. |
| CoreML compile fails (corrupt files) | Delete that model's folder, show "Model files were damaged, download again", fall back to the previously ready model. |
| Disk full | Surface the system error on the model row. Do not switch models. |
| User switches models mid-preparation | Existing generation and cancellation logic in `DictationCoordinator` applies, and `FluidAudioTranscriber` must honour `Task.checkCancellation()` between download, load and warm-up. |
| Redux on macOS 14 | Not reachable: Hush requires macOS 15. FluidAudio's `checkPlatformSupport` throws if it ever happens, and the error is shown. |
| Very long dictation (over 15 s) | FluidAudio chunks internally (sliding window). Covered by the 120 s E2E case. |

## 8. Telemetry and logging

Hush has no remote telemetry for transcription. Add OSLog lines under category `FluidAudio` that mirror WhisperKit's: model load time, warm-up time, total prepare time, and per-dictation elapsed / audio length / RTF. No transcript text in logs.

## 9. Validation plan

### 9.1 End-to-end first

Per project practice, every behaviour is first verified in the real app the way a user experiences it: build the Debug app, select the model in Settings, hold the hotkey, speak into a real microphone, and check the inserted text in a real target app (TextEdit and a browser text field). The E2E checklist:

1. Fresh install: the bundled Whisper model works offline; onboarding recommends Ultra; download, compile and switch work with visible progress.
2. Dictations of 0.4 s ("Yes."), 0.8 s, 3 s, 15 s, 60 s and 120 s in English and German.
3. Language set to German, Russian and Ukrainian with Ultra; language set to Japanese shows the unsupported state.
4. Switch Ultra → Redux → bundled Whisper → Ultra quickly; the final selection wins, with no crash and no stuck progress.
5. Quit during download; relaunch; recovery works.
6. Delete a Parakeet model while it is not active; storage figure updates.

### 9.2 Benchmark corpus and gate

Build a small Hush corpus: about 100 real push-to-talk clips recorded on a MacBook mic, English and German, including names, numbers, noisy rooms, and 20 clips under 1 s, with human reference transcripts. Store it outside the public repo if it contains personal speech.

Run `base`, `large-v3-v20240930_547MB`, Parakeet v3, Ultra and Redux on it via a test target or FluidAudio's `fluidaudiocli` and record WER, empty-output count and latency.

**Release gate**, per build, for English and German, with zero empty outputs on non-silent clips:

- Public build: Ultra becomes the recommended model only if it beats `base` on WER.
- Internal build: Ultra becomes the recommended model only if its WER is no worse than `large-v3` compressed and its latency is lower.

If Ultra fails but v3 passes, recommend v3.

### 9.3 Automated tests

- Unit: model ID → engine and `AsrModelVersion` mapping; language → `FluidAudio.Language` mapping; storage paths stay under `AIModelStorage.root`; the `ModelInfo` cache decodes old entries without `engine`; language/model compatibility rules.
- Integration (opt-in, needs downloaded models): transcribe fixture WAVs with `FluidAudioTranscriber`, including a 0.4 s clip, and assert non-empty text.
- UI test: model picker grouping, disabled quality control, unsupported-language state.

## 10. Rollout

| Phase | Content |
|---|---|
| 1. Spike | Add the package, a minimal `FluidAudioTranscriber`, hard-wire Ultra behind a debug launch argument, run the E2E checklist and the benchmark. Decide on short-clip padding. Confirm notarization. |
| 2. Product | Engine-aware `ModelInfo`, catalog, storage and Settings UI; language rules; disabled quality control; attribution. |
| 3. Recommend | Onboarding recommendation and "Recommended" label once the section 9.2 gate passes. |
| 4. Later | Parakeet custom vocabulary via CTC boosting (ties into PRD-personal-vocabulary), streaming partial text (Parakeet EOU or Nemotron streaming), Japanese via `.tdtJa`, automatic per-language engine routing. |

## 11. Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Empty output on very short clips | Medium | Silence padding, corpus with 20 short clips, release gate |
| FluidAudio API breaks between minor releases | High | Up-to-next-minor pin, bumps as reviewed PRs, integration test |
| Ultra's published accuracy does not hold on our audio | Medium | Own benchmark gate; v3 as alternative |
| First compile takes long on older Macs | Medium | Compile and warm-up inside `prepare`, behind progress UI, never on the hotkey path |
| Binary xcframework breaks signing or notarization | Low | Verify in phase 1 |
| Memory pressure with a Qwen refinement model loaded at the same time | Medium | Measure peak memory in phase 1 with refinement on |
| Licence obligations missed | Low | Attribution in About (FR-10) |

## 12. Open questions

1. Should onboarding download Ultra automatically on unmetered networks, or always ask? (Draft: always ask.)
2. Is Redux's weaker noise robustness acceptable for the "compact" slot, or should the compact option be v3 at ~500 MB?
3. Can Xcode project package references set Swift package traits, so we can drop TTS and diarization from the build?
4. Do we keep the internal build's bundled whisper-large-v3 once Parakeet is the recommended model?
5. Should "Auto-detect" with a Parakeet model warn the first time the detected text looks like an unsupported script?

## 13. References

- FluidAudio: https://github.com/FluidInference/FluidAudio (v0.18.0, 2026-10-28)
- Parakeet Ultra benchmarks: https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/ParakeetUltra.md
- Model cards: https://huggingface.co/moondream/parakeet-ultra, https://huggingface.co/moondream/parakeet-redux, https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3
- Argmax same-device benchmark: https://www.argmaxinc.com/blog/apple-and-argmax
- Short-clip latency benchmark: https://dev.to/konrad_sierzputowski_c86a/how-i-benchmarked-on-device-speech-to-text-on-apple-silicon-whisper-vs-parakeet-dne
- Research deck: https://claude.ai/artifact/W16mZpL8gVRn4Exje9mjwU
