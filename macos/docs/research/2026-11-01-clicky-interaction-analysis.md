# Clicky reference and the Hush coworker experience

Date: 2026-11-01. This corrects the product interpretation after the user tested the installed Mail-only prototype.

## Evidence and limits

- Reference: [introducing real-time graphics](https://www.youtube.com/watch?v=YlW_-hdw7hs), published by heyclicky, duration 147 seconds according to the public video metadata.
- Speech evidence: the full transcript supplied by the user in this conversation. YouTube's caption endpoint returned an empty response, then a rate-limit error; no independently retrieved caption transcript is claimed. The supplied transcript contains omitted speech and music markers, so it is not a complete technical explanation of the product.
- Visual evidence: sampled frames from a temporary public-video download. These show the original YouTube page behind generated teaching diagrams, a social-media example, and Raspberry Pi illustrations. Sampling does not establish latency, continuous interaction reliability, or model quality.
- Public implementation: [farzaa/clicky at e71105ce091d71dff4d89cf5d8d37ea1df460961](https://github.com/farzaa/clicky/tree/e71105ce091d71dff4d89cf5d8d37ea1df460961). The repository README explains that newer development is private. Its earlier companion is useful implementation evidence, not source for the current graphics engine.
- Current product claims: [Mac product page](https://www.heyclicky.com/for-mac) and [changelog](https://www.heyclicky.com/changelog), inspected on this date. These are vendor claims, not independently tested capabilities.

## What the supplied demo communicates

| Example in the supplied transcript | Interaction lesson |
| --- | --- |
| Ask about tensors while watching a lesson | The current screen supplies context; the user does not paste content into a separate conversation first. |
| Follow up about how that relates to ChatGPT | Later questions retain the subject and can revise the visual explanation. |
| Ask whether a hovering aircraft is real | Speech and visible content identify the subject together. A fluent answer alone would not prove the authenticity of a particular clip. |
| Request a 3D aircraft explanation | A richer visual is produced when requested, alongside speech. |
| Ask how to connect a camera to a Raspberry Pi | The user can move from an overview to a specific step and get a more detailed visual. |

The presenter describes graphics generated for the current request by an in-house renderer. The transcript does not disclose its scene schema, rendering technology, model prompts, verification, or local resource requirements. The demo does not establish that a 2-4B local model can reproduce arbitrary 3D explanations at the same quality or speed. It also does not demonstrate email sending, calendar scheduling, or general computer automation.

The user clarified the intended transfer to Hush: a coworker available through speech, primarily for work. Read the relevant email conversation, prepare a reply, arrange a meeting, edit text, search in a new tab, navigate, and organize files. Diagrams and 3D explanations are welcome additions. A teaching assistant or graphics generator alone would also miss this request.

## Public companion versus current product

The public companion's [OverlayWindow.swift](https://github.com/farzaa/clicky/blob/e71105ce091d71dff4d89cf5d8d37ea1df460961/leanring-buddy/OverlayWindow.swift) creates transparent, click-through surfaces that cannot become key or main windows. [GlobalPushToTalkShortcutMonitor.swift](https://github.com/farzaa/clicky/blob/e71105ce091d71dff4d89cf5d8d37ea1df460961/leanring-buddy/GlobalPushToTalkShortcutMonitor.swift) observes global shortcut transitions. [CompanionResponseOverlay.swift](https://github.com/farzaa/clicky/blob/e71105ce091d71dff4d89cf5d8d37ea1df460961/leanring-buddy/CompanionResponseOverlay.swift) positions a transient response near the cursor without taking focus. These are relevant interaction principles; no source was copied into Hush during this analysis.

The current Mac product describes screen-aware voice conversation and agent tasks. Its October changelog describes notch-based controls, drawings, and an optional expanded window. Therefore, "like Clicky" does not mean every visual must always be tiny or that no overlay may exist. For Hush, the user rejected the mandatory large Mail form. The correct default is unobtrusive conversation, with a purpose-specific visual only when it helps.

## Why the installed Hush prototype misses this

The screenshot supplied by the user reproduces the entry problem in Safari. Source inspection confirms:

1. `AssistantWindowController.open(from:)` calls `MailAssistantDestination.capture` before it can create an assistant session. A non-Mail app receives a Mail-specific error instead of a conversational entry point.
2. The controller creates a titled, resizable 420-by-640 panel, makes it key, and activates Hush. This moves the user into a form and away from their working context.
3. `DictationCoordinator.openAssistantFromChord()` opens that panel; it does not begin an assistant recording. A second dictation gesture is needed.
4. `focusedVoiceSessionID` depends on the panel being key and a Mail session existing. The raw transcript only fills the request for review. It does not start a global voice conversation.
5. The generator contract produces an email draft or clarification. There is no general conversational response path, retained coworker conversation, or assistant TTS playback.

On this Mac, preferences select `parakeet-ultra`, and all five required Parakeet cache artifacts exist. This establishes installation and selection, not a fresh runtime transcription measurement. Qwen 3.5 4B weights are also installed. The problem is missing integration and product flow, not a need to download another speech model.

The previous PRD put contextual explanations and spoken replies in phase 4, after three task adapters. That sequencing encouraged a Mail preview to become the product. The corrected PRD requires the complete voice loop first and keeps task adapters behind an independent conversation coordinator.

## Corrected interaction

```text
Working in Mail, browser, Finder, or another app
    -> hold Control + Fn and speak
    -> small Hush cursor and listening feedback; source app keeps focus
    -> release; Parakeet transcribes the instruction
    -> bounded app context + conversation + local reasoning
    -> brief spoken answer, clarification, or visible work
    -> follow up naturally, interrupt, or dismiss
```

This shortcut is the user's Hush preference, not a claim about the shortcut shown in the video. Saying "Hey Hush" is not yet a supported wake-word feature.

The state belongs to a conversation, not to a Mail editor. Retain the goal, explicit constraints, relevant facts with their sources, the current draft/event/scene, and verified outcomes. Re-read a changed target before an action. Use the existing recorder and Parakeet engine; never route assistant instructions into ordinary external dictation or proof publication. Local speech output is a first-experience requirement. Kokoro/FluidAudio remains the proposed English voice baseline, with language and quality limits from the existing model research.

Example: "Reply to Tom and arrange tomorrow at ten." Resolve the thread and contact, local date, calendar timezone, availability, and missing meeting details. Prepare a reply and event separately. "Make it warmer" revises the reply; "actually, eleven" revises the proposed time. Ask a short clarification only when context or an established preference cannot supply a required detail. Report what has actually been drafted, created, invited, or sent. A draft and a proposed time must never be reported as a completed meeting.

Visual explanation can use structured labels, arrows, nodes, edges, and later qualified 3D primitives/assets. Separate scene generation from app action execution. Bound and validate the scene before rendering; keep interactive regions explicit and dismissible. Reusable rendering primitives still permit contextual generated content, but do not justify claiming unlimited bespoke 3D geometry. Keep 3D quality and performance unqualified until measured on the target Macs.

## Acceptance for the replacement

These are required future checks, not passing results from the Mail fixture suite:

- Invoke in Safari, Mail, Finder, and a text editor; no Mail gate or compulsory main window appears, and source focus survives.
- Record one hold/release gesture using the installed Parakeet; deliver the transcript to the matching assistant turn, with no accidental paste.
- Generate a real local answer and play it through the selected local voice. Missing model/permission states are discoverable and truthful.
- Follow up twice about a draft or task without reintroducing the subject; refresh context after app/window/content changes.
- Interrupt speech to speak again; Escape stops pending work and reports any already committed effects accurately.
- Complete the email-plus-meeting journey using real adapters, including ambiguous Tom, missing duration, timezone, conflicts, partial success, and duplicate prevention.
- Search/navigate in the supported browser with visible progress and verified destinations; an unsupported adapter produces a useful limitation without disabling conversation.
- Add graphics only with separate grounding, correctness, rendering, accessibility, memory, and latency evidence. A polished image does not substitute for a correct explanation.

The research changes the specification only. It does not replace or relaunch the installed app, establish a working voice assistant, or qualify the earlier model benchmarks for these new journeys. Temporary video, tools, and extracted frames are disposable; installed Parakeet and Qwen models are retained.
