# Transcription models journey

This document defines the user-visible contract for choosing, downloading and activating speech models in **Transcription**. See `docs/PRD-parakeet-fluidaudio.md` for the reasoning.

## Product intent

The active model is always the first thing on the page. Engines come second, and individual models live one level deeper, so the common question ("what is hush using right now, and is it ready?") never requires reading a list. Downloading and activating are separate steps: the active model keeps working while another one downloads.

## Invariants

- Two engines are offered: **Parakeet** (NVIDIA Parakeet via FluidAudio) and **Whisper** (OpenAI Whisper via WhisperKit).
- Parakeet offers only the newest generation: Parakeet Ultra and Parakeet Redux.
- Every model shows its name, a one-line purpose, its download size, language coverage and the month its weights were first published. An info button next to the name opens a popover with what sets the model apart (Most accurate, Smallest, Fast, Built in), size, release month, engine, license and the full language list. Whisper dates are the original OpenAI or Hugging Face release, not the catalog upload date.
- All model files live under `~/Library/Application Support/Hush/Models/`. Parakeet uses `fluidaudio/<repository>/`.
- A download never changes the active model. A finished download shows **Use**.
- One download runs at a time. Cancel stops the download and removes its partial files.
- A download is refused up front when the volume has less free space than the model plus 15% for the compiled cache.
- The active model and the bundled model cannot be deleted. The delete alert names the model and the space it frees.
- The first-run onboarding never requires a download. It keeps using the bundled Whisper model.

## Journeys

### TM-001 - See the active model

Given the user opens **Transcription**, then the first card shows the active model's engine, name, size, language coverage, release month and a status pill: Ready, Downloading x%, Preparing x%, Needs attention or On this Mac. While preparing, a progress bar and a one-line explanation are shown.

### TM-002 - Choose an engine

Given the Transcription page, then a card for each engine shows its tagline, how many models it offers, how many are on this Mac, whether one is downloading, and an Active badge on the engine in use. Clicking a card opens that engine's model page. The window header shows a back button labelled **Transcription**, also reachable with Command-[.

### TM-003 - Download a model

Given an engine page, when the user chooses **Download**, then the row shows a progress bar and percentage and the button becomes **Cancel**. Other Download buttons are disabled with the tooltip "Another model is downloading". When the download finishes, the row shows a Downloaded badge and a **Use** button. The active model is unchanged.

### TM-004 - Cancel or recover a download

Given a download in progress, when the user chooses **Cancel**, then the partial files are removed and the row returns to **Download**. Given a failed download, the row shows the reason in red (connection lost, not enough disk space) and a **Retry** button.

### TM-005 - Activate a model

Given a downloaded model, when the user chooses **Use**, then it becomes the active model, the row shows an Active badge with preparation progress, and the hero card on the Transcription page reflects it. Dictation is available again once the status is Ready.

### TM-006 - Whisper list

Given the Whisper page, then models are grouped into Fast (under 300 MB), Balanced (300 MB to 1 GB) and Most accurate (over 1 GB), newest release first. A segmented control filters All, Multilingual and English only. A refresh button reloads the live catalog.

### TM-007 - Language support

Given a Parakeet model is active and the spoken language is one Parakeet does not support (for example Japanese), then **General > Spoken language** says so in red and offers **Switch to Whisper**, which activates the most capable Whisper model already on this Mac without downloading. On engine pages, a downloaded model that does not support the selected language shows why and its **Use** button is disabled. Hush never switches engines silently.

### TM-008 - Recognition quality

Given a Parakeet model is active, then **General > Recognition quality** is disabled and explains that Parakeet always decodes at full quality. Whisper models keep the Fast, Balanced and Best quality options.

### TM-009 - Delete

Given a downloaded model that is neither active nor bundled, when the user chooses the trash button, then an alert titled Delete "Model name"? states the space it frees, with Delete and Cancel (Cancel is the default). The engine page footer shows how many models are downloaded and their total size, with **Show in Finder**.

### TM-010 - Attribution

Given **About**, then the Speech recognition section credits Parakeet Ultra and Redux (Moondream, from NVIDIA Parakeet TDT v3, CC-BY-4.0), FluidAudio (Apache-2.0), Whisper (MIT) and WhisperKit (MIT) with links.

## Test ownership

| Journey | Automated coverage |
| --- | --- |
| TM-001 | `TranscriptionLoadingPresentationTests`, manual control center journey |
| TM-002 | Manual control center journey |
| TM-003 | `SpeechEngineTests.catalogPinsParakeet`, `FluidAudioTranscriberIntegrationTests` (real download), manual control center journey |
| TM-004 | Manual control center journey |
| TM-005 | `ModelPreparationTests`, `SpeechEngineTests.factoryRoutesByEngine`, `FluidAudioTranscriberIntegrationTests` |
| TM-006 | `SpeechEngineTests.whisperGrouping`, `SpeechEngineTests.whisperReleaseDates`, `SpeechEngineTests.metadataLine` |
| TM-007 | `SpeechEngineTests.languageSupport`, `SpeechEngineTests.generalPageLanguageMessage`, `SpeechEngineTests.languageHints` |
| TM-008 | `SpeechEngineTests.generalPageLanguageMessage` |
| TM-009 | Manual control center journey |
| TM-010 | Manual control center journey |
| Storage | `SpeechEngineTests.parakeetStorage`, `SpeechEngineTests.matchesFluidAudioContract`, `ModelStorageTests.usesApplicationSupport` |
