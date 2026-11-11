# PRD — Hush Profiles (Fully Local, MLX)

**Status:** Draft v4 (fully-local MLX, optimized for memory + latency) · **Author:** clemoji@flecs.tech · **Date:** 2026-05-25

> v1 = three cloud providers + tabbed UI. v2 = Apple Foundation Models + single cloud fallback. v3 = one local MLX model. **v4 (this) adds: aggressive idle-unload, hotkey-press pre-warm so cold-load is hidden behind the user's speech, hard memory caps via `MLX.GPU.set(cacheLimit:)`, and a model that ships outside the .app bundle.** Zero cloud, zero accounts, zero API keys, and zero LLM RAM when you're not dictating.

## 1. Problem

Hush produces Whisper-raw text. Users want light text optimization — fix grammar, shift tone (business / casual / Slack / code comment), polish without altering meaning. Small, predictable rewrites, not heavy reasoning.

## 2. The architectural decision

**Run a small instruction-tuned LLM locally on Apple Silicon via MLX.** No cloud. No API keys. No Apple Foundation Models version gate. Works on every Mac Hush already supports (M-series, macOS 15+).

This preserves the README claim verbatim — *"No cloud API. No account. No telemetry. Audio never leaves your Mac."* — and extends it to text. The rewritten text never leaves the Mac either.

## 3. Model choice — Qwen 2.5 1.5B-Instruct (4-bit MLX)

For the workload ("fix grammar, shift tone, ≤500 tokens out"), the small-model sweet spot on Apple Silicon is well-established. Comparison:

| Model | Size (4-bit) | Quality on light rewrites | Speed on M-series | Multilingual | Verdict |
|---|---|---|---|---|---|
| **Qwen 2.5 1.5B-Instruct** ✅ | ~1.0 GB | excellent for grammar + persona | 80–120 tok/s | yes (29 languages, matches Whisper's main ones) | **default** |
| Qwen 2.5 0.5B-Instruct | ~400 MB | adequate for grammar; weaker on persona | 150–200 tok/s | yes | "Tiny" alt |
| Qwen 2.5 3B-Instruct | ~2.0 GB | noticeably better persona/style | 50–80 tok/s | yes | "Best" alt |
| Llama 3.2 3B-Instruct | ~2.0 GB | strong English; weaker on non-English | 60–90 tok/s | English-heavy | skip |
| Phi-3.5 Mini (3.8B) | ~2.4 GB | strong English; weaker multilingual | 45–70 tok/s | English-heavy | skip |
| Gemma 3 1B | ~700 MB | fast; weaker instruction adherence | 200+ tok/s | yes | skip |

**Why Qwen 2.5:** it's currently the best-in-class instruction-following at <2B size, multilingual (which matters because Whisper outputs 99 languages and we don't want the post-processor to silently fail on German/Spanish/Russian dictation), and ships pre-quantized to 4-bit MLX format on HuggingFace (`mlx-community/Qwen2.5-1.5B-Instruct-4bit`).

**No "Whisper for text rewrite":** Whisper is speech-to-text only; it has no text-to-text capability. (Mentioning in case the option came up.)

**Apple Foundation Models is out of scope.** It would skip the 1 GB download for macOS 26+ users, but it excludes macOS 15/16/17 users, has narrower language coverage than Qwen, requires Apple Intelligence to be enabled, and gives us no control over model behavior. Revisit only if 1 GB download friction proves significant in v1 telemetry.

## 4. The runtime — MLX-Swift

[`ml-explore/mlx-swift`](https://github.com/ml-explore/mlx-swift) is Apple's official Swift package for MLX. The companion [`ml-explore/mlx-swift-examples`](https://github.com/ml-explore/mlx-swift-examples) exposes `MLXLLM` / `MLXLMCommon` — SPM products that already support Qwen, Llama, Phi, Gemma, Mistral with one API.

That's two new SPM deps. The repo currently has one (`argmaxinc/argmax-oss-swift` for WhisperKit). Going from 1 → 3 deps is a real cost, but each dep is first-party Apple ML tooling, mirrors how Whisper is integrated, and replaces what would otherwise be hundreds of lines of model-loading code.

Minimal call:
```swift
import MLXLLM
import MLXLMCommon

let modelContainer = try await LLMModelFactory.shared.loadContainer(
    configuration: ModelRegistry.qwen2_5_1_5b_4bit
) { progress in /* update HUD */ }

let result = try await modelContainer.perform { context in
    let input = try await context.processor.prepare(
        input: .init(messages: [
            .system(profile.systemPrompt),
            .user(rawWhisperText)
        ])
    )
    return try MLXLMCommon.generate(input: input, parameters: .init(temperature: 0.2),
                                     context: context) { _ in .more }
}
return result.output
```

About 15 LoC of real code. Same shape as the existing `WhisperKitTranscriber`.

## 5. Mirror the existing patterns (load-bearing — read this)

Every piece of new code corresponds 1:1 to an existing pattern in the repo. This is the whole point of v3.

| Need | Existing precedent (file:line) | New code mirrors it |
|---|---|---|
| Persist `[Profile]` Codable in UserDefaults | `Settings.swift:80–93` — `hotkey: KeyCombo` as JSON `Data` | Same `JSONEncoder().encode → defaults.set` for `profiles` array. |
| Enum preset with `displayName` | `Settings.swift:42–72` — `TranscriptionQuality` `.fast/.balanced/.best` | `LLMModelTier.tiny/balanced/best` mapping to Qwen 0.5B / 1.5B / 3B. |
| Static defaults + user overrides | `KeyCombo.defaultHotkey`, `ModelInfo.defaultModelID` | `Profile.seededProfiles` static array. |
| Post-process pluggable hook | `PostProcessing/TextPostProcessor.swift` — async-throws protocol, two impls already | `LLMPostProcessor: TextPostProcessor` — one new impl. **Protocol unchanged.** |
| Coordinator owns processor as stored property, swapped in `applySettings()` | `DictationCoordinator.swift:26, 68–70` | One added line in `applySettings()` swaps `postProcessor` based on active profile. |
| Async model load with progress callback | `Transcriber.prepare(modelID:progress:)` protocol + `prepareModelInBackground()` at `DictationCoordinator.swift:93–107` | `LLMModelLoader.prepare(tier:progress:)` — same shape. Coordinator calls it from a new `prepareLLMInBackground()` symmetric to the Whisper one. |
| Model lives in `~/Documents/huggingface/models/<org>/<repo>/` | `ModelManager.swift:17–26` — WhisperKit's cache layout | LLM models go in `~/Documents/huggingface/models/mlx-community/Qwen2.5-1.5B-Instruct-4bit/`. **Same root, sibling folder.** |
| In-app model picker with download progress | `Settings/ModelRowView.swift` + `Settings/SettingsViewController.swift` "Transcription models" section | The Settings "Post-processing" section reuses `ModelRowView`-style rows for LLM tier selection. |
| Section appended to single-pane settings | `SettingsViewController.swift:111–120` — `outer.addArrangedSubview(sectionTitle(...))` | One new section. No `NSTabView`. |
| Menu rebuild reactive to state | `MenuBarController.swift:57–60` — `.sink` on `phase` | `.sink` on `Settings.shared.didChange` rebuilds `Active profile ▸` submenu. |
| HUD non-blocking message | `hud.flash(message:)` (used at `DictationCoordinator.swift:135, 142`) | "LLM unavailable — pasted raw" toast if `process()` throws. The existing `(try? ...) ?? raw` at line 215 already covers the fallback. |
| `OSLog.Logger(subsystem: "com.mydear.voicetotext", category: "X")` | Used throughout | Same in LLM loader and processor. |

Eleven new things; every one of them already exists in the codebase for Whisper. The LLM is the *symmetric twin* of the Whisper module.

## 6. UX

### 6.1 Menu bar
Add `Active profile ▸` submenu item between `Hush Ready` and the existing separator (`MenuBarController.swift:43`). Submenu lists profiles with a checkmark on the active one; last item is `Edit profiles…`.

### 6.2 Settings — one new section
Appended below "Behaviour":

```
Post-processing
  Profile:          [Raw ▼]               (Add… / Delete… / Edit…)
  LLM model:        [Balanced – Qwen 1.5B ▼]   "Downloaded · 1.0 GB"
  Prompt (current profile):
   ┌──────────────────────────────────────────────┐
   │ Fix grammar and punctuation. Keep the        │
   │ speaker's wording and tone. Return only the  │
   │ corrected text.                              │
   └──────────────────────────────────────────────┘
  Test:             [Try it ▸]   → "in: '…' → out: '…' (0.6s)"
```

`LLM model:` popup shows `Tiny — Qwen 0.5B (400 MB)`, `Balanced — Qwen 1.5B (1.0 GB)` (default), `Best — Qwen 3B (2.0 GB)`. Each item shows download state. First non-tiny pick triggers a download with progress in the row, mirroring the Whisper "Use" → "Downloading" flow exactly.

### 6.3 Seeded profiles

| Profile | System prompt (first sentence) |
|---|---|
| Raw | (no LLM — bypass) |
| Polish | Fix grammar and punctuation. Keep the speaker's wording and tone. |
| Business | Rewrite as a polite, professional sentence. Concise, no filler. |
| Casual | Rewrite as a casual message: contractions, no formality. |
| Slack DM | Lowercase start, no greeting, no sign-off, ≤2 sentences. |
| Code comment | Rewrite as a terse comment: no first-person, single sentence, ending with a period. |
| Translate → English | Translate to clean, natural English. |

All editable. All deletable except Raw.

### 6.4 First-launch behavior
Default active profile = **Raw**. No download triggered, no behavior change for existing users. Picking any other profile (or going to Settings → Post-processing) triggers the LLM model download with a clear "Downloading 1.0 GB — runs entirely on your Mac" message.

This is critical: **the app does not get heavier for users who don't opt in.** Bundle size stays put.

## 7. Code delta (concrete)

| File | Action | ~LoC | Notes |
|---|---|---|---|
| `Settings/Settings.swift` | Edit | +30 | `profiles`, `activeProfileID`, `llmModelTier` keys + accessors. |
| `Settings/Profile.swift` | **New** | ~70 | Struct, `LLMModelTier` enum, seeded list. |
| `PostProcessing/LLMPostProcessor.swift` | **New** | ~80 | `TextPostProcessor` impl backed by MLX container. |
| `PostProcessing/LLMRuntime.swift` | **New** | ~160 | Actor managing the `.unloaded → .loading → .warm → .unloading` lifecycle. `MLX.GPU.set(cacheLimit:)` on unload. `idleTTL` timer. Single `preload()` and `generate()` API. |
| `App/DictationCoordinator.swift` | Edit | +25 | `hotkeyPressed()` calls `llmRuntime.preload()` if active profile uses LLM. `applySettings()` swaps `postProcessor`. Pipeline log line gets `llm_load=` and `llm_gen=` splits. |
| `MenuBar/MenuBarController.swift` | Edit | +35 | `Active profile ▸` submenu, subscribe to settings changes. |
| `Settings/SettingsViewController.swift` | Edit | +130 | New "Post-processing" section: profile picker, LLM model row, prompt editor, test button. |
| `Hush.xcodeproj/project.pbxproj` | Edit | n/a | Add `mlx-swift` + `mlx-swift-examples` (`MLXLLM`, `MLXLMCommon`) SPM packages. |
| `README.md` | Edit | +25 | New "Post-processing profiles" section. |

**Total: 3 new files, 5 edited files, ~420 LoC of Swift.** No bundle bloat (model lives in `~/Documents/...`, like the larger Whisper variants today). 2 new SPM deps (both first-party Apple ML).

The whole feature is one new conceptual module (`PostProcessing/`) that's the structural twin of the existing `Transcription/` module, scaled down (LLM is simpler than Whisper), with one extra piece of cleverness — the hotkey-press pre-warm in §8.2.

## 8. Memory & latency strategy (the load-bearing section of v4)

The user requirement is contradictory on its face: **near-zero idle RAM** but also **fast inference when triggered**. v4 resolves this with three tricks layered together.

### 8.1 LLM lifecycle — explicit state machine

```
.unloaded   (idle, 0 MB)
   ↓ hotkey pressed → start preload
.loading(progress)   (allocating, mmap, weight load)
   ↓ ready
.warm   (~1.2 GB resident, sub-second inference)
   ↓ no dictation for idleTTL seconds
.unloading   (release container, MLX.GPU.set(cacheLimit: 0), back to 0)
   ↓
.unloaded
```

Single `MainActor`-isolated state property in a new `LLMRuntime` actor. ~80 LoC. Drives the menu-bar "LLM ready / Loading / Off" indicator (sublabel of "Active profile ▸").

### 8.2 Trick #1 — Hotkey-press pre-warm (the killer optimization)

**The hotkey press is the prefetch signal.** Sequence on push-to-talk:

| Time | User action | LLM runtime |
|---|---|---|
| t=0 ms | Presses hotkey | If `.unloaded`, kick off `load()` in a Task. Don't await. |
| t=0–N ms | Speaking… | Loading in background (3–6 s typical) |
| t=N ms | Releases hotkey | Whisper transcribes (200–300 ms) |
| t=N+300 ms | Audio→text done | Await `.warm`. For dictations >2 s, this resolves instantly. |
| t=N+300 ms | — | Run inference (~600–1000 ms) |
| t=N+1.3 s | — | Paste |

**For any dictation longer than ~3 seconds (which is virtually all of them — average dictation is 5–10 s), the cold-load cost is fully absorbed by the speech window.** Net user-perceived LLM overhead is the inference time alone (~700 ms), not the cold start.

For <2 s taps, the user waits the residual load time, then sees a HUD message "Warming model…" with progress. After this first cold start, the model stays warm for `idleTTL` so the next short dictation is hot.

This trick is unique to push-to-talk dictation — the recording phase gives us a free background window. We can't use it in a chat app.

### 8.3 Trick #2 — Aggressive idle TTL with real release

`idleTTL = 90 s` default (configurable: `30s / 90s / 5min / never`). After last inference + TTL:

```swift
modelContainer = nil
MLX.GPU.set(cacheLimit: 0)   // drop the Metal buffer cache
MLX.GPU.set(memoryLimit: 0)
// Subsequent inference will hit the .unloaded → .loading path again.
```

`mlx-swift-examples` issue [#17](https://github.com/ml-explore/mlx-swift-examples/issues/17) confirms that without dropping the GPU cache explicitly, MLX retains ~1 GB even after the container is released. We do both.

On a 16 GB Mac with TTL=90s, idle memory floor is ~0 MB extra; on heavy use it's ~1.2 GB. Same RAM curve as Spotlight, Quick Look, etc.

### 8.4 Trick #3 — Bound peak memory + KV cache

```swift
MLX.GPU.set(cacheLimit: 256 * 1024 * 1024)   // 256 MB Metal cache cap
MLX.GPU.set(memoryLimit: 1_500 * 1024 * 1024) // 1.5 GB hard ceiling

let params = GenerateParameters(maxKVSize: 2048, temperature: 0.2, topP: 0.95)
```

`maxKVSize: 2048` is plenty for ≤500-token rewrites and prevents the KV cache from growing if a user pastes a paragraph-long prompt. Without it, long contexts can trigger macOS memory pressure → swap → 10× throughput drop.

### 8.5 Trick #4 — Mac-aware defaults

Detect RAM via `ProcessInfo.processInfo.physicalMemory` once on launch:

| Mac RAM | Default idleTTL | Default tier |
|---|---|---|
| 8 GB | 30 s | Tiny (Qwen 0.5B, 400 MB on disk, ~500 MB resident) |
| 16 GB | 90 s | Balanced (Qwen 1.5B, 1.0 GB on disk, ~1.2 GB resident) |
| 24 GB+ | 5 min | Balanced (same; user can opt up to Best) |

All overridable in Settings, but the defaults make the app behave correctly for the user's machine without any setup.

### 8.6 Latency budget (revised)

| Scenario | Cold path | Warm path |
|---|---|---|
| 3 s+ dictation, first use | 200–500 ms (load fully hidden) | — |
| 3 s+ dictation, model warm | — | ~1.0 s end-to-end |
| 1 s tap, first use | 3–6 s (visible cold load) | — |
| 1 s tap, model warm | — | ~0.9 s end-to-end |

The "1 s tap first use" case is the only bad path. We surface it explicitly with a HUD "Warming up…" message, and the model stays warm for 90 s after, so it's a one-time cost per session.

Add LLM latency split to the existing pipeline log line at `DictationCoordinator.swift:229`:
```
⏱️ pipeline: total=1.08s (whisper=0.32s · llm_load=0.00s · llm_gen=0.71s · insert=0.03s · post=0.02s) for 5.07s audio
```

So we can verify post-ship that pre-warming is doing its job (`llm_load=0.00s` means it was warm by the time we needed it).

## 9. Distribution — model lives outside the .app

**No model in the bundle.** The `.app` stays the same size it is today (~150 MB). The 7-line section on `BundledModels/` in the README continues to refer to Whisper only.

First time the user picks a non-Raw profile, Settings shows:

```
This profile uses an on-device LLM (Qwen 2.5 1.5B, 1.0 GB).
The model will be downloaded once and stored on your Mac.
Nothing leaves your Mac during dictation.
                                          [ Download ▸ ]
```

Tapping Download starts the HuggingFace `HubApi` download with progress shown inline in the row — same UX as downloading larger Whisper variants today (`ModelRowView`).

Storage location: `~/Documents/huggingface/models/mlx-community/Qwen2.5-1.5B-Instruct-4bit/` — sibling to the existing `argmaxinc/whisperkit-coreml/`. `ModelManager` already knows about this root (`ModelManager.swift:17–26`); we add `llmCacheRoot` next to `cacheRoot`.

If the user has the Qwen model already (from a previous install or another MLX app), we detect it and skip the download. Same `isInCache`-style check.

### 9.1 Resumable downloads

`swift-transformers` (transitive dep via `mlx-swift-examples`) supports resumable downloads with progress reporting. We get this for free — no extra work.

### 9.2 Quantization choice

Default download = `mlx-community/Qwen2.5-1.5B-Instruct-4bit`. If `…-4bit-DWQ` (Dynamic Weight Quantization — newer MLX format with better quality at same size) is available on HF, prefer it. Both ~1.0 GB; DWQ has ~10–15% lower perplexity at the same bitrate per recent MLX community benchmarks.

We do NOT offer 3-bit/2-bit options in v1. The quality drop on light text rewrite is noticeable and not worth the ~250 MB savings on a 1 GB file.

## 10. Complexity estimate

**3–4 engineering days.** The lifecycle state machine and pre-warm logic add ~0.5 day vs. v3, but the user-perceived experience is meaningfully better — and the memory floor goes from "always 1.2 GB" to "0 MB when idle."

Risk: low–medium. The unknowns:
1. **MLX memory release on container=nil** — issue [#17](https://github.com/ml-explore/mlx-swift-examples/issues/17) flags that simply releasing the container leaves ~1 GB resident. We rely on `MLX.GPU.set(cacheLimit: 0) + set(memoryLimit: 0)` to actually drop it. **30-minute spike to verify with `vm_stat` / Instruments before committing.**
2. **MLX + WhisperKit Metal contention** — both share the Metal device. Load Qwen while a Whisper transcription is in flight (rare but possible if user re-triggers fast) — does WhisperKit's CoreML cache survive? 30-minute spike.
3. **`ModelRegistry` coverage** — does `mlx-swift-examples`' built-in registry know `Qwen2.5-1.5B-Instruct-4bit`? If not, add a `ModelConfiguration` literal (~15 LoC). 15-minute check.
4. **DWQ availability on HF** — check whether `mlx-community/Qwen2.5-1.5B-Instruct-4bit-DWQ` exists at ship time. If not, fall back to plain 4-bit. 5-minute check.
5. **Multilingual quality** — when Whisper detects non-English, prepend `(The text is in <language>.)` to the system prompt. ~5 LoC. Per-profile toggle defaulted on.

## 11. What we are explicitly NOT building

- ❌ **No model in the .app bundle** — download-on-opt-in only. Bundle size stays at ~150 MB.
- ❌ No cloud LLM in v1 (no OpenAI, no Gemini, no Anthropic) — defer until a user actually asks
- ❌ No Keychain code, no API key UI — not needed
- ❌ No per-profile hotkeys — single hotkey, profile via menu bar
- ❌ No `NSTabView` refactor — append-only single-pane settings
- ❌ No streaming paste — one CGEvent, one paste
- ❌ No temperature/top-p sliders — pin to `temperature: 0.2`, mirrors how `TranscriptionQuality` hides knobs
- ❌ No custom model upload — only the 3 curated Qwen tiers
- ❌ No 3-bit / 2-bit quantization — not worth ~250 MB savings on a 1 GB file given quality drop
- ❌ No "always warm" mode — every install has an idle TTL. Power users can set it to "never" but the default is bounded.
- ❌ No protocol changes — `TextPostProcessor` and `Transcriber` are untouched

## 12. Phasing

**v1 — fully local MLX (2.5–3.5 days)**
- All 8 file changes above
- Qwen 2.5 1.5B as default tier, with Tiny/Balanced/Best switchable
- 7 seeded profiles
- "Active profile" menu-bar submenu
- Settings post-processing section
- LLM model download flow (reusing `ModelManager` patterns)

**v1.1 — only if requested**
- Apple Foundation Models as a zero-disk option on macOS 26+
- Per-profile hotkeys
- Profile import/export JSON

**v2 — only if obvious from telemetry / user requests**
- Cloud fallback (OpenAI gpt-5-nano) for users who want premium quality
- Profile-by-app auto-switch

## 13. Open questions

1. **Do we want a "very quick" Tiny tier?** Qwen 0.5B at 4-bit is ~400 MB and ~200 tok/s — strictly faster than Balanced but visibly weaker on persona shifts. Recommend shipping it as an option for users with 8 GB Macs who care about speed > quality. UI cost: zero (just another entry in the tier popup).
2. **Pre-warm LLM on launch or lazy on first dictation?** Recommendation: pre-warm if `activeProfileID != .raw`; otherwise lazy. Saves cold-start latency for active users; saves RAM for Raw-mode users.
3. **System-prompt language matching.** When Whisper detects German, do we automatically prepend "(The text is in German.)" to the system prompt? Recommendation: yes, behind a per-profile toggle defaulted on. ~10 LoC.

## 14. User-flow design (Nielsen / Norman / Cooper rationale)

The feature must obey one constraint above all else: **transcription is the core; profiles are an enhancement.** That means the default experience for every existing user, on every install, on every dictation, must be unchanged unless the user explicitly opts in.

### 14.1 Product posture (📘 Cooper §7)

Hush is a **daemonic** app — invisible until needed, communicates status when summoned. The profile feature must inherit that posture. **No popups, no tutorials, no welded-on training wheels** (Cooper). Discovery is passive: the user sees a new menu-bar item the next time they open the menu.

### 14.2 What changes — five surfaces, that's all

A heuristic evaluation pass found that the entire feature can be added by changing exactly five surfaces. Anything beyond this list is feature creep:

| # | Surface | Change | Heuristic this respects |
|---|---|---|---|
| 1 | Menu-bar dropdown | One new item: `Active profile ▸ <name>` between the status line and Settings | Nielsen #4 (consistency — extends existing submenu pattern); Nielsen #6 (recognition over recall) |
| 2 | Menu-bar icon tooltip | Append profile name: `Hush · Polish` on hover | Nielsen #1 (status visibility) without violating Nielsen #8 (minimalism) |
| 3 | HUD label during post-process | New text "Polishing with <profile>…" during a new `.postProcessing(profile)` phase. **Same HUD, same chrome, label only.** | Nielsen #1; Cooper "modeless feedback" |
| 4 | Settings | One new section "Post-processing" appended below "Behaviour" | Nielsen #4; preserves the single-pane idiom |
| 5 | Status menu item text | First menu item updates to e.g. `Polishing · Slack DM` during post-process | Nielsen #1; existing pattern (already shows "Listening" / "Transcribing") |

**Five surface deltas. Nothing else.** No new windows, no modals, no toolbar, no badges on the icon, no first-launch overlay.

### 14.3 Default = Raw (the most important design decision)

| Option | Choice | Rationale |
|---|---|---|
| A: Default = Raw, opt-in to LLM profiles | ✅ | Existing users see zero behavior change. No surprise 1 GB download. Trust signal preserved ("Audio never leaves your Mac" + "Text isn't modified"). |
| B: Default = Polish, force-download on first dictation | ❌ | Violates Nielsen #5 (error prevention — surprise download). Violates Cooper "users get humiliated when software changes their output without consent". |

The Raw default also keeps Hush's identity as a transcription tool, not a "writing assistant." Per Rams Principle 5 (unobtrusive) and Cooper §8 ("less of it would be better"), the LLM hides until summoned.

### 14.4 Discovery — three concentric rings

How does the user learn the feature exists?

| Ring | Mechanism | When |
|---|---|---|
| Inner (passive) | Next time the user opens the menu bar (they already do this for Settings), they see `Active profile ▸ Raw`. Curiosity drives a click. | Always available |
| Middle (passive) | Next time they open Settings, they see the new "Post-processing" section appended below "Behaviour". | Always available |
| Outer (gentle nudge) | After the user has completed ≥5 dictations and never opened the profile menu, the inserted-state HUD shows once: `Inserted · 12 words · Try a profile to polish ↗`. **Once. Ever.** | Heuristic, after measurable engagement |

The outer ring is the only "active" discovery, and it's a single passive nudge that decays after one display. This respects Cooper's "don't stop the proceedings with idiocy" while still nudging dormant users toward the value (Fogg trigger — but ethical, one-shot, decays).

### 14.5 Switching — two speeds

Per Cooper §5 ("Optimize for intermediates"):

| Speed | Surface | Clicks | Audience |
|---|---|---|---|
| Default | Menu bar → `Active profile ▸` → click target | 2 | Everyone. Idiom users already know. |
| Setup | Settings → Post-processing → Profile popup | 3 | Initial configuration, editing prompts |

A keyboard shortcut for power switching (e.g., `⌃⌥⌘ Space` → quick-switcher) is **deferred to v1.1.** Per Nielsen #7 it's a real concern, but the v1 telemetry need is "do users want this enough to want shortcuts" — ship the basic flow, see if it's hot.

### 14.6 "Which profile is active" — visibility by context

Per Nielsen #1 (visibility of system status) balanced against Nielsen #8 (minimalism). The active profile is shown at **five levels of loudness**, calibrated to user attention:

| Surface | Display | Visibility | Cost |
|---|---|---|---|
| Menu-bar icon (idle) | Unchanged | Always | 0 — never noisy |
| Menu-bar icon tooltip | `Hush · Polish` | On hover | 0 — opt-in |
| Menu-bar dropdown | Status line: `Polish · ready` + submenu shows checkmark | When user opens menu | Low |
| HUD during post-process | Text label: `Polishing with Polish…` | During the ~700ms post-process window only | Low |
| Settings | Full picker with profile selected | When user opens settings | High but justified |

The profile name is **whispered, not shouted**. Users who don't care never see it; users who look always find it.

### 14.7 Communicating "AI is working on your transcribed audio with profile X"

The most novel state transition. Before, the pipeline was:
```
[Listening] → [Transcribing] → [Inserted]
```

After, with a non-Raw profile:
```
[Listening] → [Transcribing] → [Polishing with Slack DM] → [Inserted]
```

The new phase `.postProcessing(profile: "Slack DM")` is added to `DictationCoordinator.Phase` and rendered identically in the menu-bar status line and HUD label. **Same components, new text.** No new visual chrome.

Why this is right (📘 Norman / Cooper):
- **Norman feedback principle**: a process taking ~700 ms must be acknowledged. Otherwise users wonder if the app froze.
- **Match between system and real world** (Nielsen #2): "Polishing with Slack DM" is what's actually happening, in plain language.
- **Conceptual model** (Norman #3): naming the profile *during* its use reinforces the user's mental model of "I picked Slack DM, and Slack DM is what's running." Self-confirming.
- **Modeless feedback** (Cooper §8): the existing HUD is already up and modeless; we extend it, not interrupt with a modal.

For Raw profile, the pipeline is unchanged — there is no `.postProcessing` phase, just `.transcribing → .inserted`. **Zero new state for the default user.**

### 14.8 Settings — Post-processing section layout

Per Cooper "Imagine users as very intelligent and very busy" + Nielsen #6 (recognition over recall), the section shows everything the user needs to understand the active profile without remembering anything:

```
Post-processing
  Profile          [Polish                          ▼]   [+ New…]  [Delete]
                   ⏎ Active profile applied to every dictation.

  Prompt           ┌────────────────────────────────────────────┐
                   │ Fix grammar and punctuation. Keep the      │
                   │ speaker's wording and tone. Return only    │
                   │ the corrected text.                        │
                   └────────────────────────────────────────────┘
                   ⏎ Edits save automatically. Empty = no LLM.

  Model            [Balanced — Qwen 1.5B (1.0 GB)   ▼]   ● Ready
                   ⏎ Larger models are slower but produce better rewrites.

  ─── Try it ────────────────────────────────────────────────────
  Sample input    "the meeting is at three i think"
  Output          The meeting is at three, I think.
                   ✓ 0.7 s · 14 tokens
                   [ Run again ]
```

Notes by principle:
- **Cooper "Save automatically"**: prompt edits autosave on focus-loss. No "Save" button.
- **Cooper "A dialog box is another room; have a good reason to go there"**: `+ New…` and `Delete` are inline; no separate management dialog.
- **Nielsen #5 (error prevention)**: Raw profile is undeletable (`Delete` disables when Raw is selected). Empty prompt → bypasses LLM (graceful).
- **Nielsen #6 (recognition)**: The prompt text is visible at all times — user doesn't need to remember what Polish does.
- **Nielsen #1 (status visibility)**: `● Ready` / `● Downloading 45%` / `● Off` modeless status on the model row.
- **Cooper "Try it" sandbox**: a synthesis of Nielsen #1, #5, #7 — fast feedback loop without needing to dictate. Especially valuable when editing a custom prompt.

### 14.9 First-time download flow

A non-Raw profile requires a 1 GB model. Per Nielsen #5 (error prevention) and #1 (visibility):

| Step | UX |
|---|---|
| 1. User opens `Active profile ▸` and clicks `Polish` | Submenu closes |
| 2. HUD slides in: `Downloading model · 1.0 GB · 0%` | Modeless, dismissable |
| 3. User dictates normally during the download | Still uses Raw — no broken state |
| 4. Download completes | HUD flashes `Polish ready — your next dictation will be polished` |
| 5. Next dictation uses Polish | Pipeline shows `Polishing with Polish…` for ~700ms |

The user is never blocked. The HUD never modally interrupts. The active profile silently remains Raw until the model is downloaded, then auto-promotes. Per Cooper "do, don't ask" and "make all actions reversible" (the user can cancel the download from the same HUD).

### 14.10 Norman 3-level critique of the proposed design

| Level | Assessment |
|---|---|
| **Visceral** (first impression) | The menu submenu addition is whisper-quiet — most users won't notice on day one. The HUD's new text feels like a continuation of the existing flow. ✅ |
| **Behavioral** (task success) | Two-click switching is fast; autosave prompts; sandbox testing; graceful fallbacks. Daemonic posture preserved. ✅ |
| **Reflective** (meaning, brand) | Profiles deepen Hush's "press → speak → paste" promise without compromising the on-device, no-cloud identity. The default user still gets exactly what they always got. ✅ |

### 14.11 What we explicitly do NOT add to the user flow

- ❌ **No first-launch tutorial / overlay / coachmarks for profiles.** Discovery is passive.
- ❌ **No "Welcome to Profiles!" modal on update.** Update is silent.
- ❌ **No persistent always-visible profile name in the menu-bar icon.** Tooltip + dropdown only.
- ❌ **No badge on the menu-bar icon to advertise the new feature.** That's the [Microsoft Office paperclip](https://en.wikipedia.org/wiki/Office_Assistant) anti-pattern.
- ❌ **No confirmation dialogs for profile switching.** Cooper "don't stop the proceedings with idiocy."
- ❌ **No separate "profile manager" window.** Inline `+ New…` / `Delete` is enough.
- ❌ **No keyboard shortcut for switching in v1.** Defer to v1.1 if telemetry warrants.
- ❌ **No per-app profile auto-switching in v1.** Deferred to v2.
- ❌ **No "Enable AI post-processing" master toggle.** The Raw profile *is* the off state. One concept, not two.

### 14.12 Heuristic-evaluation summary (📄 Nielsen 10)

A self-evaluation pass after the design:

| # | Heuristic | Status |
|---|---|---|
| 1 | Visibility of system status | ✅ Five-level loudness; `.postProcessing` phase explicit |
| 2 | Match between system and real world | ✅ "Polish", "Slack DM", "Polishing with…" — plain language |
| 3 | User control and freedom | ✅ Switch any time; cancel download; edit prompt; delete profile |
| 4 | Consistency and standards | ✅ macOS submenu+checkmark idiom; existing settings section pattern |
| 5 | Error prevention | ✅ Raw undeletable; autosave; explicit download confirmation; graceful fallback to raw text on LLM failure |
| 6 | Recognition rather than recall | ✅ Prompt visible; model status visible; profile name in tooltip + menu |
| 7 | Flexibility and efficiency | ⚠️ No keyboard shortcut in v1 — flagged for v1.1 |
| 8 | Aesthetic and minimalist design | ✅ Five surface changes; nothing for Raw users |
| 9 | Help users recognize, diagnose, recover from errors | ✅ HUD flash on LLM failure ("LLM unavailable — pasted raw"); inline status |
| 10 | Help and documentation | ✅ Inline description under each control; tooltips on hover |

**One yellow flag (#7).** Acceptable for v1; design has a built-in escape hatch (v1.1 quick switcher) if power users complain.

## 15. Sources

- MLX-Swift: <https://github.com/ml-explore/mlx-swift>, <https://github.com/ml-explore/mlx-swift-examples>
- **MLX memory ballooning issue:** <https://github.com/ml-explore/mlx-swift-examples/issues/17>
- WWDC25 — Explore LLMs on Apple Silicon with MLX: <https://developer.apple.com/videos/play/wwdc2025/298/>
- Qwen 2.5 on MLX: <https://qwen.readthedocs.io/en/latest/run_locally/mlx-lm.html>
- HuggingFace Swift client (transitive dep via mlx-swift-examples): <https://github.com/huggingface/swift-transformers>
- Idle-TTL pattern reference (SwiftLM): <https://github.com/SharpAI/SwiftLM>
- Apple Silicon LLM optimization deep-dive: <https://blog.starmorph.com/blog/apple-silicon-llm-inference-optimization-guide>
- Small-model benchmarks (May 2026): <https://llmcheck.net/benchmarks>, <https://localaimaster.com/blog/small-language-models-guide-2026>
- Repo audit cited inline by file:line throughout §5.
