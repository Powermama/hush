# Contextual editing foundation

Status: development implementation; qualification evidence below must distinguish model tests, native fixture journeys, and actual application checks. This is not a claim of broad desktop-agent accuracy.

## The defects that define the contract

Real development traces reproduced three separate failures:

1. Mail's focused compose body was `AXWebArea`, with a valid text-marker selection but no numeric `AXSelectedTextRange`. The original adapter rejected it, then incorrectly reported that the destination changed.
2. After marker support, the first real paste was verified. A correction was classified by Qwen as another `write`. The executor appended a second letter even though conversation history was present.
3. The response schema had no subject field, so the model embedded email headers in the body. Retrying the same schema could not fill the real Subject field.

These are distinct transport, action-semantics, and capability-contract defects. Increasing model size alone does not correct them. Real traces and personal message contents are not committed.

## Shared architecture

```text
Voice turn + bounded conversation
    -> observe app/window/editor and supported capabilities
    -> structured model proposal
    -> validate shape, capabilities, and source snapshot
    -> execute one native transaction
    -> read back actual state
    -> record verified outcome in conversation
```

The shared controller owns voice turns, cancellation, operation IDs, and conversation. It does not decide Mail's subject coordinates or execute model-generated scripts.

`CoworkerDocumentDestination` accepts semantic document updates: body plus supported named fields. `CoworkerRevisionDestination` supports exact-range revisions inside general text fields. A correction to a still-bound verified range remains a replacement even if the model returns `write`. An app adapter implements the appropriate contract; the controller depends on those contracts.

`CoworkerTextAccess` hides native numeric ranges versus WebKit markers. `CoworkerPaste` owns single-use dispatch, clipboard preservation, and exact read-back. This separates document semantics from accessibility transport and makes the same transaction reusable across adapters.

The Mail document adapter binds one compose window, its body, and its native subject. Both `write` and `revise` update that single document. Recipients and Send are outside the adapter's mutation surface. The model returns a separate `subject`; a deterministic validator rejects leading mail headers and known address/name placeholders in body output, with at most one model repair. Each updated field requires read-back before success.

## Apple-native API basis

Apple exposes [AXUIElementCopyParameterizedAttributeValue](https://developer.apple.com/documentation/applicationservices/1461203-axuielementcopyparameterizedattr) and [AXTextMarkerRangeCreate](https://developer.apple.com/documentation/applicationservices/3882829-axtextmarkerrangecreate) in ApplicationServices. The local macOS SDK declares the WebKit attribute constants in `AXWebConstants.h`; no dynamic private-symbol lookup is needed.

[WebKit's implementation](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/accessibility/mac/WebAccessibilityObjectWrapperMac.mm) supports selected text-marker ranges for web content while numeric selected-text ranges are specific to text controls. Marker selection being settable does not prove editability: a read-only page can also support selection. Therefore the Mail adapter additionally requires compose-window evidence, body/window membership, a unique native Subject field, and valid marker reads. It skips web content when finding native header controls.

Use AX attributes and actions before pixel coordinates. ScreenCaptureKit + Qwen vision supplies visual context, not permission to invent a control or coordinates. Accessibility timeouts, traversal/node limits, text limits, field uniqueness, and UTF-16 boundary checks are part of the adapter contract.

## Conversation and document continuity

Fading or dismissing the cursor does not start a new conversation. Current conversation memory is in-process, bounded to four recent turns, and resets after 15 minutes of inactivity or an explicit new conversation. It is not permanent memory. The latest editor state is freshly observed on each voice turn and remains authoritative for changes made since the previous response.

A model response proposes work; it cannot assert that work happened. Executor outcomes are added to history. An uncertain paste is never automatically repeated. General field revisions require the exact previously verified value and range. Document adapters bind the complete document snapshot and explicitly define their replacement scope. Manual changes during generation, a different app/window, or an unavailable field stop the action.

Mail currently bounds full-body editing to 6,000 characters so the whole body reaches model context. It does not silently truncate a larger document and overwrite the rest. Full-body replacement does not yet promise preservation of arbitrary HTML, attachments, rich signatures, or complex quoted threads. Other Mail localizations beyond verified English/German header labels need qualification. Unsupported layouts fail closed.

## Growing coverage

Add capabilities with destination-specific adapters and shared tests, not an unrestricted click loop:

| Destination | Preferred representation | Required evidence |
| --- | --- | --- |
| Native text field | AX value + UTF-16 selection | Exact-range edit, unchanged surroundings, Unicode, cancellation |
| Mail compose | Document body + native Subject | Blank draft, follow-up, duplicate prevention, subject read-back, stale snapshot |
| Browser editor | Semantic DOM/AX editing scope | Editor identity, navigation invalidation, selection/full-document boundary |
| Browser navigation | Observed link/control + native action | Destination URL/control identity and resulting page state |
| Creative app settings | Exposed native menus/controls | Stable control identity and resulting setting value |
| Pixel-only surface | Bounded image + grounded target | Separate reliability evaluation before enabling mutation |

An adapter must declare unsupported operations. General-purpose browser editing, Premiere workflows, calendar booking, and arbitrary pixel control are not implied by passing a Mail test.

## Model stack and accuracy gate

Current local stack: Qwen3.5-4B 4-bit in native MLXVLM for text and images; Parakeet Ultra through FluidAudio/Core ML for STT; Kokoro 82M through FluidAudio's ANE implementation for TTS. One Qwen container avoids loading a separate vision and reasoning model on a 16 GB Mac. Actual accelerator scheduling and peak memory must be measured under concurrent audio and inference, not inferred from weight sizes.

Task success is separate from JSON validity. Evaluate a held-out task set across multiple apps and contexts, including corrections, changed focus, duplicate text, empty fields, Unicode, and interruptions. Record task completion, unintended writes, false refusals, recovery, and p50/p95 latency. Correlate public model benchmarks only as model-selection evidence; they do not establish Hush accuracy.

Proposed release gate: at least 95% verified completion on the explicitly supported held-out task suite, zero unintended writes in the adversarial focus/cancellation suite, and measured latency/memory on both a 16 GB M2 and a 16 GB newer Mac. These are targets, not achieved results. Current automated tests and a single development Mac cannot establish population-level reliability.

## Development evidence and privacy

Use native fixture UI journeys for repeatable regressions, installed-model tests for model quality, and the installed Debug app's explicit Mail check for real cross-process behavior. The latter uses the app's real macOS Accessibility authorization; an untrusted test host is a blocked test, not evidence of an editor defect.

`--inspect-mail-editor` reads metadata and binding state. `--test-mail-editor` creates a separate recipient-free draft, writes synthetic content and subject, revises it, checks duplicate prevention, and rejects a stale snapshot. It never sends mail. All such entry points and recording code are compiled out of Release and checked with the release binary scanner. No user content is uploaded. Temporary test reports are removed after compact evidence is retained; model caches are preserved.
