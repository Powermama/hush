# Verified Messages user journey

This document is the product contract for Verified Messages. It explains intent, observable behavior, and test ownership so humans and coding agents can reason about the complete flow.

## Goal

A user can opt in to append a private `-typed with hush` proof link to dictated text or text completed inside the Hush editor. A recipient can verify that the linked message record was signed by the enrolled Mac and accepted by Hush. Original audio is not uploaded in the MVP.

## State flow

```text
Off
  -> user enables Verified Messages
Registering Mac
  -> enrollment challenge signed by the local installation key
Ready
  -> user records and Hush transcribes or refines locally
Securing proof
  -> encrypted proof reserved, uploaded, and completed
Verified link added
  -> final text and first-party private proof signature inserted together
```

If publication fails, Hush inserts the message without a proof link and shows `Inserted without Typed with Hush link`. It must never display a verified success state without a matching service receipt.

## Trust and privacy invariants

- Hey Hush assistant requests are a separate local workflow. Voice captured through Control + Fn is bound to that assistant turn UUID and bypasses persona rewriting, message insertion, activity history, and proof publication. Draft insertion from the assistant does not imply a Verified Message. See [Hey Hush](hey-hush.md), HH-001 and HH-003, with `AssistantFoundationTests.voiceContextBinding` and the assistant UI journeys.

- Verified Messages is opt in.
- The installation private key never leaves the Mac.
- Message contents are encrypted before upload.
- The decryption key exists only in the URL fragment and is not sent to the server.
- The alias service stores no decryption key and can redirect only to an immutable Hush proof.
- Original audio remains on the Mac. Only a versioned SHA-256 audio commitment is included for voice-origin messages.
- Every proof truthfully distinguishes microphone capture, text typed in Hush, and a retained Hush message reopened for editing.
- A completed edit is a new immutable proof. When the source proof is known, the revision signs its previous proof ID and commitment without copying the previous private key.
- Every proof carries a privacy-minimized signed chronology. A voice proof begins with its original recording timestamp, duration, transcription model, and local cleanup. Later revisions preserve those events and append composer voice sections, local AI refinement, manual typing, and the immutable re-sign event without copying old message text or decryption keys.
- Complete chronology is part of signed manifest version 2. Once published, a manifest version is immutable.
- Voice recorded while a Hush composer is focused is stored as ordered signed evidence sections. Raw audio remains discarded after its versioned hash is created.
- The appended link is created only after the encrypted payload and signed receipt match.
- A destination excluded by Smart mode is evaluated before signing or publication. Hush creates no proof ID, commitment, encrypted payload, receipt, or verification claim for that message.
- Secure text fields and browser address or search fields never publish a proof, even in Everywhere mode.
- Website matching uses only the current host exposed by macOS Accessibility. Hush does not read or retain browser history, paths, queries, fragments, or page contents for destination matching. When a user explicitly adds a website exception, Hush may request that website's public favicon or root HTML without cookies to show its icon. The icon is cached locally and no third-party icon service receives the domain.
- Registration, signing, publication, or verification ambiguity fails closed.

## Scenarios

### VM-001 - Enable Verified Messages

Given Verified Messages is off, when the user enables it and confirms the disclosure, then Hush creates or loads the local signing identity, enrolls the Mac, and turns the setting on only after successful registration. A cached registration belongs to exactly one proof-service origin. Switching between local development and production enrolls independently. If the configured service no longer recognizes a cached installation, Hush re-enrolls once with the existing local signing identity and retries publication without repeating onboarding.

### VM-002 - Dictate and append a proof link

Given Verified Messages is on, when a dictation finishes in an allowed destination, then Hush checks the destination policy before publication, signs the original recording and transcription chronology, completes proof publication, and inserts the signed text. The HUD shows `Securing proof` only when publication takes longer than 350 milliseconds, avoiding a flash during the normal fast path while still explaining genuine waits. Its lock, signature, and seal progress rail uses the same shell, badge, typography, and motion language as the listening and processing states. The signing badge remains graphite with a white lock and restrained blue-lilac accents. Green is reserved for completed insertion.

```text
<final message>

-typed with hush: <private proof URL>
```

The success HUD stays neutral and shows the inserted word count and destination app. The destination remains on one line and truncates at the tail when it exceeds the available width.

The returned URL uses exactly 6 Base64URL characters on the configured first-party Hush short domain. Its fragment remains the private decryption capability and is preserved by the browser during the redirect to the canonical proof page.

In Automatic mode, Hush uses the linked `typed with hush` text only for destinations verified to preserve pasted hyperlinks. The leading hyphen remains unlinked. Browsers and unknown editors receive the visible private short URL because some web editors accept HTML while silently removing its anchor. The user can select `Linked signature` to force rich text or `Always show URL` to force plain text.

### VM-003 - Publication is unavailable

Given Verified Messages is on, when proof publication fails, then Hush inserts the final message without any verification claim and displays a warning.

### VM-004 - Recipient verifies the proof

Given a recipient opens the complete private URL, then the browser preserves the private key fragment so the proof survives reload, bookmark, copy, and forwarding. The browser verifies the Hush receipt and Mac signature, decrypts locally, and shows the exact final message. The fragment is never sent to the Hush server.

### VM-005 - Edit an explicit text selection

Given the user chooses `Services > Edit Selection with Hush`, then Hush applies the same contextual resolver as the Compose shortcut. A selection inside retained Hush output reopens the complete message. An unrelated selection opens a blank draft and is never preloaded or claimed as Hush-authored source.

The macOS Service remains an explicit-selection fallback. The menu-bar panel does not duplicate this action.

### VM-006 - Open the contextual Hush editor

Given another app has keyboard focus, when the user presses the configurable Compose shortcut, then Hush resolves context in this order:

1. when text is selected, a retained Hush output in the same app that is at least 95% similar and encloses that selection;
2. a blank private Hush draft.

The resolver never guesses from caret proximity. With no selection, Hush always opens a clean composer. It has no short-lived timeout: a selected message can be reopened 30 minutes later or any time within the selected history-retention period. Automatic recovery requires at least 20 characters so a common short phrase cannot be mistaken for a previous message. An arbitrary pasted or selected passage is never loaded into the editor. Hush reads focused text only long enough to resolve context and retains no surrounding document content. A partial selection inside a known Hush message expands to the complete message and every adjacent stale Hush signature, so completion creates one updated message and one proof. When the user completes the edit, Hush re-reads the exact destination range and requires a 100% match with the snapshot captured when the editor opened. If the source changed, Hush copies the completed message instead of overwriting the document.

The editor has two explicit workspaces. `Compose` is a focused direct-editing surface with the complete current text, word count, restore action, and one acceptance control. The window, header, footer, cards, text, borders, and controls use AppKit materials and semantic system colors so the complete editor remains coherent and readable in both macOS Light and Dark appearances. Layer-backed surfaces re-resolve their semantic colors when the effective system appearance changes. `Edit with AI` is one ephemeral local conversation. Before the first request, Hush gives two brief context-sensitive ideas and ranks up to three relevant personas locally from the destination app and message text. `More` reveals the complete persona list without making it permanent chat chrome. The ready on-device model remains a compact control in the bottom composer. The source text is supplied privately as conversation context and is not pinned as a permanent message or artifact. Return sends a request and Shift-Return adds a line. User requests use compact trailing bubbles and Hush replies use full-width, readable conversation typography. While a response is being prepared, an inline disclosure moves through safe observable stages such as `Reviewing context`, `Planning response`, `Writing response`, and `Checking result`; its dots animate quietly unless Reduce Motion is enabled. After completion it becomes `Thought for …`; expanding it shows a short request-specific Hush-authored activity summary, never the model's private reasoning or raw scratchpad. Questions, critique, brainstorming, and advice remain ordinary assistant messages. An editable artifact appears inline only when Hush creates, rewrites, translates, or directly changes usable text. Each artifact remains at its original point in the thread as a numbered selectable version with local generation duration and, when the provider reports it, output-token usage. Apple Foundation Models retains its transcript and MLX retains its `ChatSession` and KV cache until the editor closes, after which the conversation is discarded. The selected persona applies to that conversation. The user can choose an earlier version, open any artifact in Compose for direct edits, or accept the exact current version. Generated text never replaces the current version until a local AI request with an artifact succeeds. Ordinary conversation replies never alter the accepted text. Qwen uses a validated native `create_artifact` tool call instead of inferring artifacts from assistant prose. A malformed, duplicate, or truncated tool call fails closed and the broken turn never enters the retained history. Cached MLX models load directly from the validated local Hugging Face snapshot, share one warm-up task across UI and generation requests, and run one background first-generation warm-up before becoming ready. Hush records provider, persona, refinement input, and refinement time only for the artifact the user ultimately accepts. Restoring the original removes generated-version and conversation state.

The AI prompt includes inline microphone input. Listening reuses the same live 28-bar waveform as the global HUD, and local transcription changes that waveform to the HUD's animated aurora processing sweep. Recording, live level feedback, local transcription, and errors stay inside the prompt and never open the global HUD. There is no conditional send-arrow control: Return sends and Shift-Return adds a line. A one-line prompt stays compact. Additional lines grow the composer to a capped height, after which the native text view scrolls internally. The transcript is inserted into the prompt for review and is sent only when the user presses Return. Because it is an instruction rather than accepted message content, it is not recorded as a signed voice section in the final artifact.

Text completed in this editor is retained only when local history retention is enabled. It is excluded from voice activity, spoken-word, and time-saved metrics.

### VM-007 - Publish a truthful editor proof

Given Verified Messages is enabled, when the user completes a Hush editor message, then Hush publishes and inserts the same private proof signature used by dictation. The signed manifest identifies whether the text was typed in Hush or reopened from retained local Hush history. A reopened message carries forward the original signed recording chronology, records each later composer voice section and manual edit independently, and creates a new immutable proof that references the previous proof commitment. The old URL continues to verify the old wording and the new URL verifies the revision.

The recipient story describes human actions instead of application mechanics. A composer proof can show `Message started in Hush`, each voice section with its capture time, duration, and local model, optional local AI refinement, and final signing. A later revision carries that signed chronology forward and adds `Edited and re-signed` with its timestamp and prior-proof link.

### VM-008 - Dictate multiple sections inside one composer

Given a Hush composer is the focused window, when the user records a section in `Compose`, then the recording binds to that editor session UUID at capture start. Hush transcribes and cleans the section locally, inserts it at the current composer selection, and appends one ordered voice evidence record containing the transcript, model, duration, sample rate, capture time, and audio hash. The section is not independently published and no proof link appears inside the draft. When the user starts recording from the microphone inside `Edit with AI`, the transcript is inserted into the conversation prompt instead and does not become signed message content unless the resulting artifact is accepted.

The next recording cannot start while the prior section is still transcribing, so an earlier result is never cancelled by a later capture. If the bound composer session closes before transcription completes, Hush copies the transcript instead of inserting into another editor or app. Completing the composer publishes one proof containing all typed edits, ordered voice sections, optional profile refinement, and prior proof reference.

### VM-009 - Exclude apps and websites from proof publication

Given Verified Messages is enabled, Smart destination mode is the default. It automatically hides signatures in known terminal apps and lets the user add personal app and website exceptions from the compact `Where signatures appear` section. The native app picker accepts multiple applications in one action and explains the standard Command-click and Shift-click selection controls. A website rule applies to the exact host and its subdomains, but never to lookalike hosts. This allows a proof on `x.com` while excluding `chatgpt.com` in the same browser.

When dictation or editor completion targets an excluded destination, Hush inserts only the final message. It does not sign, reserve, upload, or complete a proof. The first exclusion in a destination shows a quiet `Signature hidden` HUD notice; later insertions remain quiet. The normal inserted state never implies that an excluded message was verified.

Everywhere mode bypasses terminal, personal app, and website rules. Secure text fields and browser address or search fields remain excluded in every mode. The current website host is resolved ephemerally through macOS Accessibility and only user-created exception hosts are stored. Website exception rows show the site's public favicon when available. Hush requests it directly without cookies and caches it locally for up to 30 days. A generic globe remains the fail-closed visual fallback.

## Test mapping

| Journey | Automated evidence |
| --- | --- |
| VM-001 | `ProvenanceAPITests.enrollsAndPublishesWithHonoService` covers real Swift-to-Hono enrollment. `missingPublicationInstallation` covers the fail-closed stale-registration signal used for one-time automatic re-enrollment. Settings interaction is verified manually. |
| VM-002 | `ProvenanceAPITests.enrollsAndPublishesWithHonoService`, `appendsSignatureLink`, `createsRichSignatureLink`, `avoidsRichLinksInUnverifiedDestinations`, `rejectsInvalidProofAliasLength`, and `signsOpenAPIExpiryAtRoundingBoundary` cover publication, plain and rich formatting, sanitized-link fallback, the exact alias contract, and exact signed wire timestamps. The sibling web app tests the real 6-character short-link redirect. The Release app build covers pasteboard integration. |
| VM-003 | Swift unit coverage verifies unavailable registration. The visible warning is verified manually. |
| VM-004 | Owned by the sibling web app Playwright proof journey and backend tests. |
| VM-005 | The Release build validates the native Services declaration and provider selector. Cross-app contextual-menu behavior is verified manually. |
| VM-006 | `TextContextMatcherTests` covers exact matching, strict 95% recovery, partial-selection expansion, duplicate-signature removal, unrelated-selection rejection, app isolation, clipboard exclusion, no age cutoff, proof-parent, pre-AI source, chronology propagation, and 100% fail-closed replacement validation. `HushSelectionEditorStateTests`, `PersonaSuggestionRankerTests`, `ConversationalEditPromptTests`, and `SelectionEditorJourneyTests` cover explicit version selection, truthful manual-edit provenance, contextual persona ranking, direct cached-snapshot resolution, protocol-tag removal, truncated-response rejection, native Qwen artifact tool calls, streamed output, Return-to-send, Shift-Return newline entry, multiline composer growth, removal of the redundant send arrow, multi-turn conversation continuity, safe thinking disclosure, inline listening and processing visuals, generation metadata, the accepted current-text control, and complete Compose and Edit with AI screenshots in forced Light and Dark appearances. The opt-in real Qwen conversation journey covers advice, polite edit requests, acknowledgements, and follow-up revisions against the cached MLX model. The macOS smoke journey verifies contextual resolution through Accessibility and the Compose shortcut. |
| VM-007 | `ProvenanceAPITests.completeVoiceRevisionChronology` covers the complete initial recording, cleanup, composer voice, manual edit, and revision event order. The remaining provenance tests cover manifest signing, immutable revision encoding, and publication. The sibling web app Playwright journey verifies typed-origin and revision recipient copy. |
| VM-008 | `ProvenanceAPITests.revisionAndVoiceSections` covers ordered, signed voice evidence and parent proof round trips. The Release app build covers editor session routing, while the native smoke journey checks focused-session insertion and closed-session clipboard fallback. |
| VM-009 | `VerifiedMessageDestinationPolicyTests` covers terminal defaults, personal app exceptions, secure fields, exact and subdomain website matching, lookalike-domain rejection, URL normalization, Everywhere behavior, and browser address or search fields. `WebsiteIconLoaderTests` covers safe favicon discovery and offers an opt-in live fetch-and-decode integration check through `HUSH_FAVICON_E2E_HOST`. `VerifiedMessageDestinationJourneyTests` verifies the compact settings flow, automatic exclusions, discoverable multi-app selection, website rule creation, favicon presentation, removal, and visible layout in the real app. |

## Change rule

Every bug fix starts by reproducing the closest journey above. Add the smallest regression test at the layer where the defect occurred, then run all lower layers and the complete affected journey.
