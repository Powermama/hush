# Hey Hush user journey

**Status, 2026-11-01:** local coworker prototype, not release-qualified. The normal entry is now a voice-controlled Hush cursor with a short state label and an Esc control. The old Mail form is retained only as a legacy fixture. No typed conversation field, Preview, Copy, Apply, or Insert button belongs in the coworker experience. See the [PRD](../PRD-hey-hush.md) and [vision audit](../research/2026-11-01-mac-vision-selection.md) for capabilities that still need implementation and qualification.

## HH-001 - Talk where the user is working

Hold **Control + Fn**, speak, and release to submit. Hold again to interrupt a spoken reply and give the next instruction. The cursor's microphone affordance is an accessible click-to-start/stop alternative. There is no wake-word listener or continuous microphone recording. The source app keeps focus and its caret. Neither Mail nor a focused Hush window is required.

Capture reuses the installed Parakeet engine and existing recorder. Each assistant recording has its own UUID; stale or cancelled transcripts cannot reach another conversation or become ordinary dictation. Assistant requests bypass persona rewriting, clipboard insertion, activity history, and Verified Messages publication. They never become proof-bearing user messages.

Context currently consists of bounded Accessibility text, selected text, app/window identity, and exposed control metadata. Visual requests now capture a bounded source-window screenshot through ScreenCaptureKit and pass the image to native MLXVLM. The same installed Qwen 3.5 checkpoint supplies both text and image inference through one container. Screen Recording permission is required, and missing permission is reported explicitly. A still screenshot does not establish video understanding or reliable arbitrary pixel targeting. Qwen 3.5 2B/4B is selected independently of ordinary dictation's optional rewriting preference. No 9B or cloud fallback is used.

Hush AI > Assistant (Beta) shows local intelligence, transcription, voice setup and all three assistant permissions. General Permissions covers Microphone and Accessibility for dictation; Screen Recording belongs only to Assistant setup. Assistant setup cannot report Ready while a required component or screen access is missing. Dictation itself does not require screen access. An immediately successful screen permission request is honored. Page controls take priority over browser chrome in bounded AX context. Opening an observed video link does not by itself require a screenshot; explaining its visual content still does.

After navigation, a URL alone is insufficient to advance. The native executor waits within a bounded verification window for one populated page and honors its exposed loading state before recapturing context. Web fields use the shared native paste transaction after confirming focus and the complete replacement selection; an AX value setter may report success without updating a controlled HTML input. Browser address-field setters use bounded read-back. Neither path retries an uncertain mutation. Long navigation landmarks are traversed after main page content within the same bounded context budget. `CoworkerSequenceTests.browserDocumentReadiness` covers premature navigation verification; actual Safari checks remain required for field behavior.

Single-page web apps may expose a new URL and `AXLoaded=true` while their old content remains. Native navigation therefore also requires a changed semantic content sample for a changed URL, stable across observations for 350ms. Page headers, search inputs and suggestion subtrees do not count as new results. An observed Search button with one populated bound search field shares the Return-key search postcondition; ambiguous buttons remain unverified. The 12-second limit and no-retry rule remain. Coverage: `CoworkerOperationContractTests.pageTransition`, `siteSearchArrival`, and the opt-in `CoworkerSearchEvaluation` recorded-input replay. See [reproduction and validation](../research/2026-11-02-search-result-readiness.md).

## HH-002 - See, interrupt, and refine the work

The default surface is a lilac Hush cursor, a compact truthful status capsule, a quiet source/shortcut label, and an always available **esc** control. States include Listening, Understanding, Thinking, Writing your draft, Refining your draft, Speaking, Your turn, Draft updated, and Stopped. The cursor never hides the system pointer. It follows the user’s mouse with restrained smoothing, and holds position when the pointer reaches its controls so they remain clickable. An action briefly outlines its actual target while Hush stays beside the user’s pointer. It does not animate fictitious mouse clicks.

All conversational input is voice. Hush asks necessary follow-up questions aloud; the label becomes **Your turn**. Hold Control + Fn to answer or refine the task, for example “make it warmer” or “actually at eleven.” The question cue fades after eight seconds; the bounded conversation remains available for the next spoken turn. No typed input or keyboard button appears. A small read-only speech bubble shows the sentence currently playing and closes with playback. Requested captions, diagrams, and actionable errors can disclose a small secondary surface. Captions are available through the cursor's context menu; settings stay outside the conversation.

Escape stops recording, generation, queued actions, and playback, and ends the conversation. Keyboard Escape, the cursor's Esc button, and Dismiss Hush clear the in-memory turns, previous draft binding, pending proposal, captured context, and sequence checkpoints. The next Control + Fn or microphone invocation captures the current app and starts with no previous conversation. Without Escape, spoken follow-ups retain context, including after the cursor fades. The existing 15-minute inactivity expiry remains an additional limit. Resetting conversation memory does not delete text already written into another app or development trace files.

Pressing Escape again while stopped dismisses the cursor immediately. Its native Esc button accepts the first click even while another application keeps focus. A 350 ms visible cue precedes mutations so a queued edit can be cancelled. If Paste has already been sent, Hush finishes read-back and reports the actual result; it cannot retract an event already delivered to another app. That late result must not restore a cleared conversation or its old edit target. Another recording waits until this verification finishes. An outside key press or click during acting cancels further work without ending the conversation. No cancelled turn may later paste or start speaking. No automatic retry follows an uncertain mutation.

Use semantic Light/Dark materials, restrained lilac, SF typography, a static state dot and input-driven listening bars. The companion follows the user's pointer while a separate outline identifies an actual bound target. Panels are nonactivating and clamped to the display. Completed work fades after three seconds; Stopped fades after 1.8 seconds. Another voice invocation returns the cursor. Reduce Motion disables the fade and smoothing.

### Checked sequences and visible waiting

Structured generation uses fixed JSON formatting outside strings. Model-generated draft text retains spaces, Unicode and escaped paragraph breaks. This prevents the observed repeated-whitespace stall from consuming the full generation budget. Context JSON keeps URLs unescaped; the executor still validates every proposed URL. The shared runner's admission gate rejects any continuation after an unverified receipt, independently of the model or adapter. Coverage: `AssistantGrammarTests.nativeTokenMask`, `CoworkerOperationContractTests.promptURLSerialization`, `admissionAfterUncertainResult`.

The 2026-11-02 combined-operation candidate (`openPage` and `searchPage`) is not enabled in normal builds. Its model-interface regression is recorded in the [source and operation evaluation](../research/2026-11-02-source-patterns-and-operation-evaluation.md). Only an explicit Debug launch with `HUSH_BUNDLED_BROWSER_ACTIONS=1` exposes it. The installed prompt and individual operations remain the default pending model and live execution qualification.

Direct navigation accepts an HTTP(S) destination with `target=0`, including a known homepage for a website named in speech. It does not require that address to appear in the screenshot or user transcript. The model must ask when the address is unknown or ambiguous and must select result links from fresh observed evidence. A nonzero target is still bound to the exact captured link; script/file URLs and embedded credentials are rejected. The current tab is used unless the user requests a new one. External `openLink` still requires supplied or observed evidence because it ends with unverified dispatch. This separates navigation destinations from element references without adding site-specific workflows.

For a nonzero link target, native code resolves the captured address from that ID. The model can leave content empty; any redundant model-written URL is ignored rather than executed or compared. This avoids copying errors in tracking parameters and preserves the captured destination exactly. A missing ID never falls back to the model's URL. Coverage: `CoworkerOperationContractTests.referencedLinkResolution`; the live first-video failure that motivated this is recorded in [search readiness](../research/2026-11-02-search-result-readiness.md).

The Google web-search operation verifies its HTTPS search endpoint and exact decoded `q`, accepting Safari's added client parameters and form-encoded spaces. Other links retain strict destination checks, including video IDs. Coverage: `CoworkerOperationContractTests.directNavigation`, `searchArrival`; opt-in installed-Qwen decision evaluation: `CoworkerNavigationEvaluation`. Research and live outcomes: [navigation contract](../research/2026-11-02-navigation-contract.md).

One spoken goal can continue through up to eight actions within a 180-second monotonic budget. Each action gets one dispatch, native verification, and a fresh context binding before another decision. The original goal and compact checkpoints accompany each observation. Screenshots are requested again when useful, rather than continuously recording video. A repeated proposal against unchanged evidence, an uncertain result, or exhausted budget stops continuation. Outside input during a subsequent decision also stops it. A follow-up is still a voice turn in the same bounded conversation.

The cursor reports actual stages: **Preparing local AI**, **Reading this window**, **Preparing action controls**, **Choosing the next action**, **Checking the plan**, the action itself, and **Checking the result**. After two seconds, a quiet caption shows elapsed time for the current stage. Continued steps show **Step 2**, etc., without pretending to know the total number of future steps. There is no fabricated percentage, ETA, or generated reasoning transcript. Success appears only after native verification; a model's proposed message is not proof that an action happened.

Model adapters share `CoworkerGenerating`, the validated request/reply contract, and the native result boundary. Audio remains independently replaceable. This does not imply arbitrary MLX architectures are supported: each replacement must pass its own runtime, accuracy, latency, and memory qualification.

Grammar masking constrains JSON structure and the currently available action names. Character-count limits are checked natively before dispatch, including the 300-character subject limit and per-request shortening limits. They are not expanded into token grammar states: the former subject-length grammar caused a reproduced 58-65 second preparation stall on the development M5. Cancelled requests check cancellation before loading, after acquiring the shared model container, and before preparing a grammar. A cancelled turn cannot consume another full preparation pass when it reaches the front of the queue.

## HH-003 - Write and revise directly in the editor

An explicit request to write or revise authorizes the bound edit. Hush applies it directly, without a preview or execution button. It never sends mail. A draft is rendered into native plain text, RTF, and escaped HTML, with deterministic paragraph formatting. Arbitrary HTML, inline styles, nested lists, and rich signatures still need destination-specific qualification.

Before insertion, native code binds and rechecks the process, window, field, complete current text, and UTF-16 selected range. Secure fields, terminals, browser chrome, unreadable editors, and changed destinations are excluded. Native activation is followed by another context check; Paste is targeted to that process. A read-back of the complete expected value is required before claiming success.

An omitted native `AXValue` is not automatically an unsupported editor or an empty document. If the read succeeds without a value (or returns `noValue`), Hush accepts an empty string only when `AXNumberOfCharacters` independently reports a numeric zero. Failed reads, missing/nonzero counts, invalid value types, and invalid selections remain blocked. This shared native-editor behavior is covered by `CoworkerTests.emptyNativeEditor`. Debug-only `--inspect-notes-editor` checks the live binding without editing; `--test-notes-editor` creates a separate note and checks insertion, Unicode, revision without duplication, and stale-snapshot rejection. Actual Notes insertion remains unqualified until that live check passes; see the [refusal diagnosis](../research/benchmarks/2026-11-02-notes-editor-refusal.md).

After verified insertion, Hush retains the exact inserted range and complete resulting field value in memory. A follow-up revision replaces that range, preserving surrounding text and the signature. It requires the same app/window/editor, unchanged full value, and a caret or selection within that draft. If the user edits the document, moves elsewhere, or changes the target, Hush stops with an explanation instead of appending another draft or overwriting unrelated text.

The clipboard lease preserves original item boundaries and types and restores them only after verification and only if Hush still owns the clipboard. A newer user copy wins. An unverified paste asks the user to check the field and is never silently repeated. Conversation history is bounded to four turns and expires after 15 minutes of inactivity. Native state, not model prose, determines whether an edit happened.

### Document-aware follow-ups

Mail compose windows bind a document with separate body and native Subject fields. The structured response has a separate subject value. Both write and revise replace that one bounded body, so a model misclassification cannot append a second email. Headers and invented address/name placeholders are rejected before insertion. Recipients and Send remain untouched. Each voice turn reads a fresh snapshot; changes during generation stop the transaction. Complex HTML and long threads are not yet qualified.

Other native editors retain the generic exact-range adapter. A follow-up on the same unchanged verified range replaces that range even when the model returns write instead of revise, preserving surrounding text. Document adapters share `CoworkerDocumentDestination`; native and WebKit text transports share `CoworkerTextAccess` and `CoworkerPaste`. See the [scalable editing foundation](../research/2026-11-01-contextual-editing-foundation.md).

Regression mapping: `testFollowUpMisclassifiedAsWriteStillReplacesOnlyTheVerifiedText`, `unavailableEditor`, `unicodeEditorRanges`, and `mailDocumentContract`. Installed-model evidence: `CoworkerLiveTests.mailDocumentFollowup`. Actual Mail checks use Debug-only `--inspect-mail-editor` and `--test-mail-editor`; blocked permissions and unverified writes must not be recorded as passes.

## Other requested journeys

| Journey | Current implementation and remaining work |
| --- | --- |
| HH-004: Finder organization | Not implemented. Requires folder binding, collision handling, a move journal, and undo. |
| HH-005: Browser work | The checked loop and native operations for New Tab, grounded current-tab navigation, observed search-field fill/submit, and observed-link activation are implemented. Verification requires a tab-count increase, exact field read-back, or the expected page URL. Missing AX evidence stops the run. “Click here” remains user-pointed and cannot automatically continue. External search/open-link dispatch is also unverified and cannot chain. Actual Safari/YouTube execution, consent dialogs, multiple windows, result classification, and playback still require live qualification. |
| HH-006: Explanations | Local spoken answers from Accessibility context and optional window screenshots; simple label-based flow diagrams. Paired synthetic-image tests confirm the installed Qwen checkpoint uses image pixels through MLXVLM. They do not qualify real desktop understanding, generated 3D scenes, or diagram factual quality. |
| HH-007: Arrange a meeting | Resolves a proposed event into an escaped local ICS draft with timezone. Opening it is not a booking or an invitation. Contact resolution and verified calendar execution remain unimplemented. |
| HH-008: Find a Premiere Pro setting | Screenshots and native exposed-control presses are connected. Arbitrary model-chosen pixel coordinates and multi-step Premiere navigation remain unimplemented. User-pointed “click here” is separate from model grounding. |
| HH-009: Research and summarize news | Summarizes exposed text and opens searches. The shared navigation loop is implemented; multi-page evidence gathering, source attribution, and real-site execution remain unqualified. |
| HH-010: Multiple email drafts | Single bound draft and follow-up revisions are implemented. Batch orchestration, thread switching, recipient binding, and per-message verification remain unimplemented. |

## Test mapping and evidence boundaries

Developer builds have an explicit, per-launch diagnostic recorder under `#if DEBUG`; Release builds exclude it and its controls entirely. It stores local bounded per-turn inputs, model output, validation stages, and errors for reproduction, without audio or uploads. See [development diagnostics](../research/2026-11-01-development-diagnostics.md). The real controller's missing-target failure trace is covered by `testDevelopmentTraceExplainsFailedInsertion`; recorder limits, disable behavior, permissions and replay input fidelity are covered by `CoworkerDiagnosticsTests`.

| Behavior | Automated coverage |
| --- | --- |
| Cursor-only default, no Mail gate or typed controls | `AssistantJourneyTests.testCursorIsTheDefaultSurface`, `testGlobalEntryDoesNotRequireMail` |
| Spoken turn, immediate native paste, spoken revision replaces original, preserved signature, Dark appearance | `AssistantJourneyTests.testSpokenTurnFollowUpAndInsertion` |
| Follow-up question and voice answer without a form | `AssistantJourneyTests.testClarificationContinuesByVoiceWithoutAForm` |
| Inactive-app Esc click, stopped dismissal, cursor following, idle fade, read-only speech bubble | `AssistantJourneyTests.testEscapeDismissesStoppedCursorFromAnotherApp`, `testCursorFollowsMouseAndCompletionDisappears`, `testSpeechBubbleIsReadOnlyAndEscapeStopsIt` |
| Escape prevents a late draft insertion | `AssistantJourneyTests.testCoworkerEscapeCancelsLateReply` |
| Escape clears conversation and old edit binding in a reused editor; keyboard and cursor button agree | `CoworkerTests.escapeStartsFresh`, `cancelAfterDispatch`; `AssistantJourneyTests.testEscapeStartsFreshInReusedEditor`, `testEscapeButtonStartsFreshInReusedEditor` |
| Outside-input cancellation retains follow-up context; late errors after Escape cannot restart speech | `CoworkerTests.interruptedActionKeepsConversation`, `cancelledVerificationFailure`; [reset validation](../research/benchmarks/2026-11-02-escape-conversation-reset.md) |
| Stale recording UUID, cancelled generator, chord release, grounded links, escaped calendar content, strict action decoding | `CoworkerTests` |
| One spoken goal continues with fresh evidence; visible elapsed stage and Escape before the next action | `testOneSpokenGoalContinuesAfterFreshObservation`, `testSequenceShowsElapsedWorkAndEscapeStopsNextStep` |
| Goal retention, fresh IDs, uncertain dispatch stops, no-progress rejection, eight-action cap, cancellation, adapter contract | `CoworkerSequenceTests` |
| Per-step debug inputs preserved within existing storage limits | `CoworkerDiagnosticsTests.stepEvidence` |
| Screen permission is visible separately in native settings | `PermissionJourneyTests.testAssistantOwnsScreenAccessAndLocalModelSetup` |
| Safari sibling-tab semantics, contextual search routing and selective vision | `CoworkerSequenceTests.nativeTabSemantics`, `contextualSearchRouting`, `contextualVision` |
| Real Safari controls versus the real local model/controller | Debug-only `--test-browser-controls` and `--test-browser-agent`; require normal Hush permissions and leave their test tab open. No pass is inferred from a missing permission or a partial run. |
| Installed-model sequence decisions and ambiguous ranking clarification on synthetic AX observations | `CoworkerLiveTests.browserSequence` (opt-in; not live Safari evidence) |
| Unsupported model completion claims cannot override native receipts or pollute retained history | `CoworkerSequenceTests.unsupportedCompletionClaim` |
| Native token masking, Unicode, complete EOS | `AssistantGrammarTests.nativeTokenMask` |
| Text limits and cancellation before preparation | `CoworkerTests.textLimits`, `cancelledBeforePreparation`; `CoworkerSequenceTests.capabilitySchema` |
| Installed-tokenizer preparation latency, separated from model inference | `AssistantGrammarTests.installedTokenizerPreparation` (opt-in through `HUSH_GRAMMAR_PROFILE=1`); [preparation diagnosis](../research/benchmarks/2026-11-01-grammar-preparation.md) |
| Legacy proposal validation, insertion guards, clipboard ownership, voice context binding | `AssistantFoundationTests` |
| Legacy Mail fixture: rich paste, changed destination, truncated output | `AssistantJourneyTests.testReviewAndFormattedInsertionPreserveSignatureInLightAppearance`, `testStaleDestinationNeverReceivesDraft`, `testEscapeStopsGenerationAndTruncatedOutputCannotBeInserted` |
| Opt-in installed Qwen / Parakeet / Kokoro integration | `CoworkerLiveTests.localConversation`, `nativeVision` |

The final focused run passed 34 checks, including all 11 assistant UI journeys and two installed-model integrations. See the [validation record](../research/benchmarks/2026-11-01-coworker-validation.md) and [per-test results](../research/benchmarks/2026-11-01-coworker-xctest-summary.json).

The coworker UI fixture uses a real NSTextView and native pasteboard but injected model responses, simulated recording/transcripts, and silent voice output that exercises utterance callbacks. It validates UI behavior and insertion continuity, not recognition accuracy, audible quality, cross-process AX compatibility, or M2 speed. The legacy Mail fixture is not the product entry.

Release qualification still requires held-out real-model conversation tasks, real microphone/playback cancellation, Apple Mail and web editor AX testing, permission/focus races, rich formatting validation, full-stack memory/latency on a 16 GB M2, and screenshot-to-action end-to-end tests. The research record contains failed model-quality trials; fixture success does not erase them.

The checked-sequence implementation and its paired model evaluation are recorded in [sequence validation](../research/benchmarks/2026-11-01-sequence-contract-validation.md). This record includes the first revision's regression, the later improvement, cold-start timing, and remaining model errors.


## HH-012 - Set up local Assistant models

Workflow > Hush AI contains only two native cards: Personas and Assistant (Beta). Each shows its real setup status and a relevant action. Personas shows the chosen writing style; Assistant shows Ready only when its setup prerequisites are ready. The Assistant card offers guided setup directly. There is no global model catalogue and no Hey Hush row in the menu-bar panel. Control + Fn remains the voice entry point.

Model management belongs to the workflow that uses it. Personas has an expandable **Writing engine** section for Apple Intelligence and the two Qwen options. Each downloadable engine supports Download, Use and Remove. Assistant has **On this Mac** controls for its selected Qwen engine, current transcription model and Kokoro voice. Each row explains the model's role, storage and state. Downloads remain shared, so the same Qwen files serve both workflows without duplication. Bundled transcription files cannot be removed separately; Apple Intelligence remains managed by macOS.

Assistant has one **Set up Assistant** button. Setup checks microphone, Accessibility, screen access, the independently selected Qwen model, shared transcription model and Kokoro. It skips ready components, guides native permission requests, downloads missing files through the existing runtimes, and prepares Kokoro before reporting Ready. Permission requests never count as grants. Cancel stops owned work; Resume skips completed work; failures offer Retry. A cold voice runtime reuses its files.

Kokoro now reports the actual current-file transfer percentage from the SDK's public URLSession counters. Its pronunciation download uses the SDK progress callback. File percentages are explicitly labeled as file progress, not overall setup completion. Unknown content lengths have no fabricated percentage. Loading and voice warming are separate stages; no timer simulates progress. This is presentation only and preserves the SDK's download, cache, verification and retry behavior.

Model states are text, not disabled buttons: Active uses accessible green text, while cached voice files that still need preparation say Downloaded. Download and Use are quiet accent-colored actions. Installed models have a standard macOS More menu containing Remove. Removal asks for native confirmation with the effects on shared workflows. There is no Test voice button. Hush rejects removal while recording, editing, responding, loading or setting up. Removing an active persona engine turns it off. Removing the active transcription download switches to the bundled default. Kokoro removal stops playback, waits for synthesis/preparation, unloads its runtime and removes only its own model and phonemizer directories. Parakeet files are preserved. Missing Assistant models route Control + Fn to setup.

General Permissions covers dictation; screen access belongs to Assistant. Processing stays local. Model downloads and websites opened by browser actions use the internet. macOS dialogs still require user approval and may request a relaunch.

Mapping:

- `AssistantSetupFlowTests`: skip ready components, ordered preparation, failure/resume, request versus grant, cancellation/double-start, isolated voice-file removal/reinstall.
- `AssistantSetupTests`, `ModelStorageTests`, `ModelPreparationTests`: independent readiness, actual bundled files, private caches and model preparation.
- `VoicePreparationProgressTests`: unknown lengths, truthful stage labels, voice-only transfer filtering, real intermediate percentages from a controlled local URLSession transfer, compact native menu without the Assistant entry.
- `PermissionJourneyTests`: clean landing page, contextual model controls, disclosure collapse/expand, native editor, permission ownership, setup cancel/resume, removal confirmation, Kokoro percentage display, light/dark/compact layouts.

Setup and progress UI snapshots use explicitly injected debug-only states. They do not grant real TCC permissions or download test models. The removal UI test cancels the sheet; deletion/reinstall uses temporary fixture directories. The progress integration uses an actual local HTTP transfer, not a model download. Full first-run model downloads, interrupted SDK transfers and every live macOS permission dialog remain device/network qualification tasks.
