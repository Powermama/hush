# hush AI journey

This document defines the user-visible contract for the hush AI area: Live Write, the AI writing feature, and Assistant, the voice coworker. See the Live Write PRD for the reasoning.

## Product intent

Each AI feature is one product with one switch. Its status says, in one line, where it stands, and its card offers the one next step: download an engine, set up, open System Settings, retry. Personas are optional on top of Live Write, not a choice the user has to make. Everything runs on the Mac; model downloads are the only network use.

## Invariants

- hush AI lists Live Write and Assistant as cards with an app-style icon, a one-line description, a status line, a switch and a chevron into the feature's page. The switches work in place.
- Live Write is off for new installs. Turning it on picks the best ready engine (Qwen 3.5 4B, then Apple Intelligence, then Qwen 3.5 2B, ranked by hush's live persona benchmark). With no engine ready it stays on, says that dictation works as usual meanwhile, and offers `Download Qwen 3.5 4B`.
- With Live Write on and no persona, a request becomes the requested text and anything else is cleaned up. A chosen persona applies on top. Turning Live Write off leaves the engine loaded for Assistant.
- Settings from before Live Write keep their behaviour once: AI on with a persona becomes Live Write on with that persona; AI on with `No persona` stays plain dictation (Live Write off).
- Assistant is on unless the user turns it off. Turning it on starts setup when something is missing. Turning it off keeps models and permissions, and its shortcut shows `Assistant is off. Turn it on in hush AI.` instead of opening.
- During Assistant setup the card shows the current step; at a permission step it offers `Open System Settings` and `Cancel`.
- Live Write's Writing engine is one always-visible list, recommended first: Qwen 3.5 4B, Apple Intelligence, Qwen 3.5 2B, then ChatGPT. Each row has its status and one action (Use, Download, Continue with ChatGPT); the engine in use says Active.
- ChatGPT is the user's own plan through Sign in with ChatGPT. `Continue with ChatGPT` first says what leaves the Mac (what is dictated, sent to OpenAI with storage off; no screen, no password, no chats), then opens the browser. Connected, the row shows the model and `Using ChatGPT plan`; its More menu holds the model, `Manage Usage…` and `Disconnect ChatGPT…`. Disconnecting revokes the session and says when OpenAI did not confirm it.
- When the plan's limit is reached or ChatGPT cannot write, Live Write writes that dictation on the best engine on this Mac, or inserts the user's words, and says so after inserting. Plan requests pause for 15 minutes after a limit.
- While the AI writes, the HUD shows `Writing` and the engine (`Qwen 3.5 4B`, `Apple Intelligence`, or a cloud mark and `ChatGPT`), nothing more.

## Journeys

### AI-001 - See and switch the AI features

Given the user opens hush AI, then Live Write and Assistant each show their status and a switch. Turning a switch changes the feature in place; the chevron or the card opens its page.

### AI-002 - Turn on Live Write

Given Live Write is off, when the user turns it on, then it uses the best ready engine and shows `Ready on <engine>`. Without a ready engine, the card shows the download action and the progress of the download.

### AI-003 - Write without a persona

Given Live Write is on with `None` selected, when the user dictates "write Tom that I'm running ten minutes late", then hush inserts the finished message; a plain dictation is inserted cleaned up.

### AI-004 - Turn Assistant on and off

Given Assistant is on but not set up, when the user turns it on or chooses `Set up Assistant`, then guided setup starts and can be cancelled and resumed. Given Assistant is off, the shortcut does not open it.

### AI-005 - Write with a ChatGPT plan

Given Live Write's engine list, when the user chooses `Continue with ChatGPT`, then hush explains what is sent, the browser handles sign-in and consent, and the ChatGPT row offers `Use`. With ChatGPT in use, dictations are written on the plan and the HUD shows the cloud mark; at a limit the dictation is written on this Mac and a note says so.

## Test ownership

| Journey | Automated coverage |
| --- | --- |
| AI-001 | `PermissionJourneyTests.testLandingShowsWorkflowsAndModelsStayInContext`, `testCompactWindowKeepsNavigationAndModelsReachable`, `testAISettingsInDarkAppearance` |
| AI-002 | `LiveWriteSettingsTests`, `PermissionJourneyTests.testLiveWriteUsesSharedModelsAndKeepsOptionalPersonas` |
| AI-003 | `LiveWriteSettingsTests.personaIsOptional`, `DictationPromptTests`, opt-in `PersonaLiveTests` |
| AI-004 | `LiveWriteSettingsTests.assistantSwitch`, `PermissionJourneyTests.testOneSetupButtonCanCancelAndResume` |
| AI-005 | `ChatGPTConnectionTests` (protocol, tokens, errors, Keychain, callback), `PermissionJourneyTests.testLiveWriteUsesSharedModelsAndKeepsOptionalPersonas` (ChatGPT row); live sign-in is manual |
