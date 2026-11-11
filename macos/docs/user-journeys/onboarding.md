# Onboarding user journey

This document defines the first-run contract for Hush.

## Product intent

The onboarding is a native four-step product demo, not a settings checklist. It mirrors Hush's visual language and lets a new user experience the complete value chain in under a minute: private local transcription, optional local personas, and optional signed creation proof. Each step has one obvious forward action. System access appears only in context after the user taps the microphone.

## Invariants

- A fresh launch never reads or writes the user's Documents folder. Transcription and language models live under Hush's Application Support directory.
- The welcome step appears before any system permission dialog.
- The window uses the focused 1280 by 860 onboarding canvas, native macOS controls, Hush aurora surfaces, a centered Hush title, and a four-part progress rail.
- Microphone and Accessibility access are requested only after the user taps the voice-test microphone. Both are required to complete the guided practice so the first real dictation can listen and type successfully.
- The bundled transcription model is self-contained, including its tokenizer. It prepares exactly once in the background, never requires a first-run download, and remains loaded for immediate dictation.
- The voice test uses the landing-page microphone orb as its main control and shows the real floating Hush HUD while listening and processing, so the tutorial matches everyday dictation.
- Practice audio is transcribed through the normal local speech pipeline, is never inserted, and is never written to activity history.
- The transcript is shown only after local processing completes. The screen does not imply live word recognition while recording.
- Local personas are optional. The persona step presents one recommended Apple Intelligence switch and a visual persona ring without forcing profile configuration.
- Verified Messages is optional. Enabling it creates or restores a signing identity protected by Secure Enclave or Keychain.
- Verified Messages records a signed trail for microphone capture, Hush composition, and refinement history. This is meaningful evidence of origin and history, not an absolute biological-identity guarantee or an AI-audio detector.
- Hush never asks the user to invent, copy, or store a signing password. The signing private key never leaves the Mac.
- Failure to enable Verified Messages never prevents onboarding completion, and no verification claim is shown after a failure.

## Journeys

### OB-001 - Value-first welcome

Given Hush has not completed onboarding, when it launches, then the user sees `Talk and your Mac` with the rotating value phrase, local privacy promise, four-step progress rail, and no permission prompt.

### OB-002 - Contextual voice setup

Given the user reaches `Test your voice`, when they tap the microphone, then Hush presents the in-app permission sheet. The sheet explains Microphone and Accessibility in plain language. Hush invokes each system request only after its corresponding row is selected, and Continue unlocks after both are ready.

### OB-003 - Hands-on local transcription

Given permissions and the local model are ready, when the user continues from the permission sheet, then the microphone orb moves through listening and local-processing states while the real floating HUD shows `Listening` and then `Processing`. Hush records the suggested sentence, finishes automatically or when the user taps again, hides the HUD, and presents the persistent `Heard clearly` result. Nothing is inserted or saved.

### OB-004 - Optional local personas

Given the voice test succeeded, when the user continues, then Hush presents `Enable your local personas` with the Apple Intelligence switch and persona ring. Enabling it configures on-device personas. Leaving it off changes the forward action to Skip and does not block setup.

### OB-005 - Optional private proof

Given the user continues from personas, when they reach `Proof it's really you`, then Hush presents one Attach proof switch and a visual creation-history card. Enabling proof prepares the local signing identity and reveals microphone capture, local cleanup, and signed-encrypted history. The status says `Voice-origin verified` and does not claim biological identity or AI-audio detection.

### OB-006 - Finish setup and learn where Hush lives

Given proof is off, ready, or failed, when the user chooses `Set up Hush`, then Hush briefly gathers Voice, Personas, Proof, and Shortcuts into the Hush mark. The handoff confirms that the private workspace and Dashboard are ready on this Mac, teaches that Hush remains available from the menu bar, and then opens the Dashboard. Onboarding is marked complete, while Persona and Proof choices remain editable in Hush settings. The animation communicates local setup state and never implies that an online profile or cloud account is being generated.

## Test ownership

| Journey | Automated coverage |
| --- | --- |
| OB-001 | `OnboardingJourneyTests.testFreshInstallCompletesImmersivePrivateJourney`, `OnboardingComponentTests.welcomePage`, `ModelStorageTests.usesApplicationSupport`, and `ModelStorageTests.bundledModelIsOfflineComplete` |
| OB-002 | `OnboardingJourneyTests.testFreshInstallCompletesImmersivePrivateJourney` and `OnboardingComponentTests.contextualVoiceSetup` |
| OB-003 | `OnboardingJourneyTests.testFreshInstallCompletesImmersivePrivateJourney` |
| OB-004 | Both `OnboardingJourneyTests` journeys and `OnboardingComponentTests.optionalCapabilities` |
| OB-005 | Both `OnboardingJourneyTests` journeys and `OnboardingComponentTests.optionalCapabilities` |
| OB-006 | Both `OnboardingJourneyTests` journeys and `OnboardingComponentTests.completionHandoff` |
