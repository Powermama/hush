# PRD - Hush Personal Vocabulary

**Status:** Ready for implementation planning  
**Date:** 2026-08-06  
**Platform:** macOS 15+  
**Initial provider:** WhisperKit  
**Product promise:** Correct a distinctive term once. Hush asks before remembering it, then writes it correctly on the next dictation.

## 1. Executive decision

Build one focused, local learning loop for names, brands, acronyms, and specialist terms.

The first release solves this exact journey:

```text
The user says:       "Space Hotel"
Hush inserts:        "space hotel"
The user corrects:   "Spazzz Hotel"
Hush asks:           Remember "Spazzz Hotel"?
The user confirms:   Remember
The user says again: "Space Hotel"
Hush inserts:        "Spazzz Hotel"
```

Use Apple frameworks for observing and understanding the correction, SwiftData for local persistence, and a small provider adapter around WhisperKit. Do not add a second language-model pass, a custom neural model, or a third-party fuzzy-matching package.

The correction becomes reliable through two complementary layers:

1. **Recognition hint:** Hush supplies relevant remembered terms to WhisperKit as decoder prompt tokens. This increases the chance that WhisperKit emits the canonical spelling directly.
2. **Deterministic correction:** Hush replaces a confirmed spoken alias such as `space hotel` with the exact canonical form `Spazzz Hotel` after transcription and before persona refinement or insertion.

The recognition hint improves recall. The deterministic correction provides the guarantee when the learned alias appears in the raw transcript.

## 2. Why this architecture

### 2.1 WhisperKit is not the dictionary of record

Open-source WhisperKit supports `DecodingOptions.promptTokens` and `prefixTokens`. These condition decoding, but they are probabilistic and do not guarantee an exact spelling.

WhisperKit Pro offers audio-based custom vocabulary through a parallel auxiliary model, but its current documentation says that the feature is extensively tested on Parakeet models and disabled for Whisper models until those combinations are better tested. Hush must not make its first vocabulary release depend on that path.

Therefore:

- Hush owns the vocabulary and its behavior.
- WhisperKit receives best-effort recognition hints.
- A deterministic Hush stage owns exact canonical spelling.
- The provider can be replaced later without migrating the user's vocabulary.

### 2.2 No custom machine-learning model in v1

Hush does not yet have a representative labeled dataset of accepted and rejected correction suggestions. A custom classifier trained now would encode synthetic assumptions and be harder to explain than a conservative score based on observable signals.

The first release uses:

- `NLTokenizer` for language-aware word boundaries.
- Swift `CollectionDifference` for the bounded before-and-after comparison.
- `NLLanguageRecognizer` for language metadata.
- `NLTagger` for person, place, and organization signals where supported.
- `NSSpellChecker` as one rarity signal, never as the decision maker.
- Deterministic safety gates and a transparent confidence score.

A Core ML classifier may replace only the ranking function after Hush has enough local, consented outcome data. Exact replacement remains deterministic.

### 2.3 No always-on typing monitor

Hush observes only text that Hush just inserted, for a short bounded period. It does not inspect unrelated typing or retain surrounding message content.

This is both the privacy boundary and the quality boundary. A correction immediately after a Hush insertion is meaningful training data. Arbitrary typing elsewhere is not.

## 3. Scope

### 3.1 In scope for v1

- Detect one short correction inside the most recent Hush insertion.
- Suggest remembering a distinctive term without stealing focus.
- Save the canonical spelling and the observed spoken alias locally.
- Apply confirmed entries everywhere in v1.
- Give WhisperKit relevant recognition hints.
- Apply exact, word-boundary-aware replacement after transcription.
- Preserve the canonical form through optional persona refinement.
- Let the user inspect and delete remembered terms.
- Suppress repeated suggestions after dismissal.
- Record local quality and latency measurements without message content.

### 3.2 Explicitly deferred

- App, domain, and persona scopes.
- Automatic learning without confirmation.
- Manual pronunciation recording.
- Contacts, Calendar, browser, or document imports.
- Team vocabulary sync.
- Phonetic fuzzy matching.
- A custom Core ML correction classifier.
- WhisperKit Pro or FluidAudio custom-vocabulary integration.
- Model training, LoRA, or on-device weight updates.
- A full Suggestions inbox.
- Transcription model naming and release-date redesign. That is a separate product concern and should have its own PRD.

## 4. Experience principles

### 4.1 Correct once

The natural correction is the teaching action. The user should not have to open Settings to teach a brand name.

### 4.2 Ask before learning

Hush never silently turns an edit into a global replacement. The user confirms the exact mapping.

### 4.3 Never interrupt dictation

Candidate detection happens after insertion and outside the recording, transcription, refinement, and insertion critical path.

### 4.4 Exact where trust matters

Once confirmed, the output spelling is not left to a generative model.

### 4.5 Explain the mapping

The prompt shows both sides:

```text
Remember "Spazzz Hotel"?
You said "space hotel"
```

The user can understand precisely what will happen next time.

### 4.6 Easy recovery

The user can dismiss the suggestion, delete a remembered term, or undo an applied correction. No hidden learning state.

## 5. Canonical end-to-end journey

### Journey PV-01: Learn “Spazzz Hotel” from one correction

#### Preconditions

- Accessibility permission is granted.
- Personal Vocabulary learning is enabled.
- No existing entry covers `space hotel`.

#### First dictation

1. The user places the cursor in a destination text field.
2. The user records: `Please send the brief to Space Hotel today.`
3. WhisperKit returns: `Please send the brief to space hotel today.`
4. Hush inserts that text normally.
5. Hush records only the insertion locator, inserted text, insertion time, destination bundle identifier, and language. The surrounding document is not persisted.
6. The user changes `space hotel` to `Spazzz Hotel` within 30 seconds.
7. An Accessibility value-change notification wakes the observer.
8. Hush reads only the recently inserted range when the destination supports range reads.
9. Hush tokenizes the original and current range, computes the narrow difference, and identifies one phrase substitution.
10. The candidate detector passes the correction because:
    - the edit is inside the Hush-inserted range;
    - most of the sentence is unchanged;
    - the edit is one short phrase;
    - `Spazzz` has distinctive spelling;
    - the edit is not punctuation, grammar, filler removal, or sensitive data.
11. Hush waits for a short editing-settled debounce, then shows a compact non-activating suggestion near the completion HUD:

```text
Remember “Spazzz Hotel”?
You said “space hotel”

[Not now]                         [Remember]
```

12. The destination app retains keyboard focus.
13. The user chooses `Remember` by mouse, keyboard shortcut, or VoiceOver action.
14. Hush saves the mapping immediately:

```text
canonical: Spazzz Hotel
aliases:   [space hotel]
language:  detected language
scope:     everywhere
```

15. The suggestion becomes a brief confirmation:

```text
Spazzz Hotel remembered
```

16. The confirmation dismisses automatically.

#### Second dictation

1. The user later says: `The new campaign for Space Hotel is ready.`
2. Before recognition, the WhisperKit adapter selects `Spazzz Hotel` as a relevant hint and encodes it into the decoder prompt within the provider's token budget.
3. WhisperKit transcribes the audio.
4. If WhisperKit emits `Spazzz Hotel`, no replacement is needed.
5. If WhisperKit emits the learned alias `space hotel`, the deterministic vocabulary stage replaces that complete token sequence with `Spazzz Hotel`.
6. If persona refinement is active, the canonical term is passed as a protected term in the existing single refinement request.
7. Hush validates that the protected canonical term survived refinement.
8. Hush inserts: `The new campaign for Spazzz Hotel is ready.`

#### User-visible guarantee

When the raw transcript contains the confirmed alias `space hotel` as a complete phrase, Hush writes `Spazzz Hotel` exactly. This guarantee does not depend on WhisperKit honoring a prompt or Qwen choosing the right spelling.

### Journey PV-02: Dismiss a suggestion

1. The same detection flow produces a candidate.
2. The user chooses `Not now` or lets the suggestion expire.
3. Hush does not save a vocabulary entry.
4. The same pair enters a local cooldown.
5. Hush does not show it again immediately.
6. A repeated identical correction on a later dictation may be suggested once more with increased evidence.

### Journey PV-03: Delete a remembered term

1. The user opens Settings > Transcription > Personal Vocabulary.
2. The user sees:

```text
Spazzz Hotel
Heard as “space hotel”
```

3. The user deletes the entry.
4. Hush removes it from recognition hints and deterministic replacement immediately.
5. Future dictations return to the provider's unmodified output unless the term is learned again.

### Journey PV-04: Destination cannot be observed safely

1. Hush inserts text into a destination that does not support bounded Accessibility range reads, or the field is secure.
2. Insertion still succeeds normally.
3. Hush does not observe, infer, or suggest a correction.
4. No error interrupts the user.

## 6. Interaction specification

### 6.1 Suggestion timing

- Observation window: 30 seconds from successful insertion.
- Editing-settled debounce: 700 ms after the latest relevant value change.
- Suggestion lifetime: 10 seconds.
- Stop observing on a new Hush dictation, focus leaving the destination control, a substantial rewrite, a secure field, or window expiry.

These are product defaults and must be validated in the E2E journey before release.

### 6.2 Suggestion surface

Use the existing non-activating HUD window infrastructure so the destination remains first responder.

Requirements:

- One title, one explanatory line, and two actions.
- `Remember` is the primary action.
- `Not now` is visually quiet.
- Escape dismisses.
- Return confirms only when the suggestion has keyboard accessibility focus. It must not intercept Return intended for the destination app.
- VoiceOver reads the canonical form, observed alias, and the effect of remembering.
- Reduced Motion uses a fade instead of scale or spring motion.
- No success notification if persistence fails.

### 6.3 Settings surface

The v1 management UI is intentionally small:

```text
Personal Vocabulary
Terms Hush learned after you corrected a dictation.

Spazzz Hotel
Heard as “space hotel”                         Delete
```

Provide search and deletion. Manual creation, scopes, usage analytics, and pronunciation recording are deferred.

## 7. Detection architecture

### 7.1 Standardized pipeline

```text
Hush inserts text
        ↓
InsertionObservation captures the exact inserted range
        ↓
AXObserver receives a value-change notification
        ↓
Read only the Hush-inserted range
        ↓
NLTokenizer tokenizes original and edited text
        ↓
CollectionDifference isolates the changed token span
        ↓
NLLanguageRecognizer + NLTagger + NSSpellChecker add signals
        ↓
CorrectionCandidateDetector applies hard gates and confidence scoring
        ↓
Confidence high enough?
        ↓
Non-activating “Remember Spazzz Hotel?” suggestion
        ↓
VocabularyStore persists the confirmed mapping
```

### 7.2 Accessibility boundary

At insertion time, store an ephemeral `InsertionObservation`:

```swift
struct InsertionObservation: Sendable {
    let element: AXUIElement
    let insertedRange: CFRange
    let insertedText: String
    let insertedAt: ContinuousClock.Instant
    let destinationBundleIdentifier: String?
}
```

Implementation rules:

- Use the Accessibility range APIs already required for insertion.
- Prefer `kAXStringForRangeParameterizedAttribute` to read only the known range.
- Account for a small length delta caused by the user's correction.
- Never fall back to copying the whole document or clipboard.
- Never observe secure text fields.
- Keep one active observation at a time.
- Keep the observation in memory only.

### 7.3 Token-level comparison

Use `NLTokenizer(unit: .word)` with the detected language. Compare token values and ranges rather than raw character offsets so punctuation and composed Unicode characters do not create false candidates.

Use `CollectionDifference` to find the minimal token deletion and insertion. Convert the result into a substitution only when the unchanged prefix and suffix align unambiguously.

Examples:

| Inserted | Edited | Result |
|---|---|---|
| `space hotel` | `Spazzz Hotel` | Candidate |
| `space hotel.` | `Spazzz Hotel.` | Candidate |
| `space hotel` | `space hotel!` | Reject: punctuation only |
| `send to space hotel` | `Please send the final brief to Spazzz Hotel tomorrow` | Reject: substantial rewrite |
| `um space hotel` | `Spazzz Hotel` | Reject: filler removal mixed with term correction |

### 7.4 Candidate hard gates

A candidate is eligible only when all conditions pass:

- Edit overlaps the latest Hush-inserted range.
- Edit occurs inside the observation window.
- Exactly one contiguous substitution remains after token alignment.
- Removed and inserted sides are each one to four words.
- At least 70 percent of surrounding tokens are unchanged.
- The candidate is not punctuation, whitespace, or casing alone.
- The destination is not a secure field.
- Neither side matches sensitive-data patterns.
- The pair is not already remembered or in cooldown.

### 7.5 Confidence signals

Add transparent points after hard gates:

| Signal | Effect |
|---|---|
| Mixed case, internal capitals, repeated letters, acronym, or digits in the canonical form | Strong positive |
| `NLTagger` identifies a person, organization, or place | Positive |
| `NSSpellChecker` treats the canonical token as unusual | Weak positive |
| Same correction observed twice | Strong positive |
| More than two surrounding words changed | Negative |
| Common function word on either side | Negative |
| Alias shorter than four characters | Strong negative |

`NSSpellChecker` is only a feature. Brand names are expected to look misspelled, and ordinary misspellings are not automatically vocabulary.

### 7.6 Suggestion policy

- Suggest on the first correction only when confidence is high, as with `space hotel` to `Spazzz Hotel`.
- For medium-confidence pairs, wait for the same correction twice.
- Never auto-save in v1.
- `Not now` creates a cooldown, not a permanent block.
- Repeated dismissal becomes a stronger negative signal.

## 8. Runtime correction architecture

### 8.1 Provider-independent contract

Add vocabulary as a separate domain dependency rather than embedding it in `WhisperKitTranscriber`:

```swift
struct VocabularyHint: Sendable, Equatable {
    let canonicalForm: String
    let spokenAliases: [String]
    let language: String?
}

protocol TranscriptionVocabularyProviding: Sendable {
    func hints(for context: TranscriptionContext) async -> [VocabularyHint]
}

protocol TranscriptionProvider: Sendable {
    func transcribe(
        samples: [Float],
        language: String,
        fallbackCount: Int,
        vocabularyHints: [VocabularyHint]
    ) async throws -> RawTranscription
}
```

The existing `Transcriber` protocol can evolve toward this contract without adding another provider in v1.

### 8.2 WhisperKit hint adapter

For WhisperKit:

1. Build the hint set when the vocabulary, selected model, or language changes, not during every dictation.
2. Select only relevant remembered canonical terms.
3. Format them as short natural text examples, not instructions.
4. Encode them once with the Whisper tokenizer already shipped with the selected model.
5. Cache the resulting token IDs in memory using `(modelID, language, vocabularyRevision)` as the key.
6. Reuse that cached token array as `DecodingOptions.promptTokens` for every matching transcription request.
7. Prefer recent and repeatedly used terms when Whisper's prompt-token budget is full.

The prompt is a hint. It must never be the only correction mechanism.

`DecodingOptions` is request-scoped, so Hush still attaches the cached token IDs to each transcription request. This does not mean re-reading SwiftData or tokenizing every dictionary word again. Current open-source WhisperKit does not expose a supported cross-request prompt KV-cache API. The public `promptTokens` array is therefore passed on each request, while all vocabulary selection, formatting, and tokenization work is cached by Hush. The decoder may perform a small prompt prefill for each request, but the hint set is intentionally short and this cost must stay inside the latency budget.

Do not use `prefixTokens` to force vocabulary into the beginning of the transcript. Prefix tokens are unsuitable for a term that may occur anywhere in the utterance.

### 8.3 Deterministic alias corrector

After WhisperKit returns raw text:

1. Normalize transcript and aliases for comparison using Unicode canonical normalization, locale-aware case folding, and whitespace normalization.
2. Tokenize with `NLTokenizer`.
3. Build phrase matches using complete token boundaries.
4. Resolve overlaps longest alias first.
5. Replace the matched source range with the exact stored canonical form.
6. Preserve surrounding punctuation and whitespace.
7. Apply every source range at most once.
8. Return both corrected text and structured replacement metadata.

For the learned entry:

```text
canonical: Spazzz Hotel
alias:     space hotel
```

these inputs behave as follows:

| Raw transcript | Result |
|---|---|
| `visit space hotel` | `visit Spazzz Hotel` |
| `visit Space Hotel` | `visit Spazzz Hotel` |
| `visit space   hotel` | `visit Spazzz Hotel` |
| `visit space hotel.` | `visit Spazzz Hotel.` |
| `visit space hotels` | unchanged |
| `visit myspace hotel` | unchanged |

This exact token-sequence matcher is the fastest and safest v1 behavior. Do not use edit-distance or phonetic fuzzy matching globally. A fuzzy match can silently change an unrelated word, which is more damaging than missing a correction.

If WhisperKit produces a different recurring alias, the user can correct it once and Hush adds that observed alias to the same canonical entry after confirmation.

### 8.4 Efficient matching

For a small vocabulary, a precomputed dictionary keyed by the normalized first token is sufficient and avoids a dependency:

```text
normalized first token
        ↓
candidate aliases sorted longest first
        ↓
boundary-safe phrase comparison
```

If benchmarks later show that thousands of entries exceed the latency budget, replace the internal index with an Aho-Corasick trie behind the same protocol. Do not add that complexity before measurement.

### 8.5 Persona and Edit with AI

When refinement is active:

- Correct aliases before Qwen so the prompt contains `Spazzz Hotel`.
- Include only terms actually matched in the transcript as protected terms.
- Instruct the existing single refinement request to preserve those terms exactly.
- Validate matched canonical terms after refinement.
- Repair only a known protected-term mutation. Do not run another generation.

There remains one optional Qwen pass, not a vocabulary pass followed by a persona pass.

## 9. Persistence

Use SwiftData, which Hush already uses for local activity data, for the vocabulary store.

Conceptual model:

```swift
@Model
final class VocabularyEntry {
    @Attribute(.unique) var id: UUID
    var canonicalForm: String
    var aliases: [String]
    var languageCode: String?
    var createdAt: Date
    var updatedAt: Date
}
```

Store suggestion cooldowns separately:

```swift
struct VocabularySuggestionKey: Codable, Hashable, Sendable {
    let normalizedAlias: String
    let normalizedCanonicalForm: String
}
```

Persistence requirements:

- Activate a saved entry without restarting Hush or reloading WhisperKit.
- Enforce normalized alias uniqueness.
- Merge a confirmed new alias into an existing canonical entry.
- Detect replacement loops before saving.
- Do not persist the surrounding message, destination text, or raw audio.
- Exclude vocabulary content from logs and analytics.

## 10. Privacy and security

- Everything remains on the Mac.
- Observe only the latest Hush-inserted range.
- Keep the observation window bounded and ephemeral.
- Never observe secure fields.
- Never write the source sentence to logs.
- Never store raw audio for learning.
- Filter passwords, keys, tokens, payment data, government identifiers, email addresses, URLs, and long numeric strings before suggestion creation.
- Clearing Personal Vocabulary deletes remembered entries and suggestion cooldowns.
- Verified Messages may record that deterministic vocabulary normalization occurred, but never the private term, alias, or surrounding content.
- If Accessibility access is denied or a destination does not expose range reads, fail closed for learning while preserving ordinary dictation.

## 11. Performance budgets

| Operation | Target |
|---|---|
| Select prompt hints | <5 ms p95 for 1,000 entries |
| Encode WhisperKit prompt hints | <10 ms p95, cached by active vocabulary revision |
| Deterministic alias correction | <5 ms p95 for a 500-word transcript and 1,000 entries |
| Candidate detection | asynchronous, no insertion delay |
| Persist confirmed entry | <20 ms p95 |
| Additional LLM load for vocabulary | never |

Cache the provider-ready prompt tokens by:

- active transcription model;
- language;
- vocabulary revision.

Invalidate the cache only when one of those values changes.

## 12. Failure behavior

| Failure | User experience |
|---|---|
| Accessibility range cannot be read | No suggestion; dictation remains unaffected |
| Candidate is ambiguous | No suggestion |
| Vocabulary persistence fails | Keep the popup visible with a concise retry state; do not claim success |
| Prompt token encoding fails | Continue without hint; deterministic correction still works |
| Alias corrector fails unexpectedly | Insert raw transcription and log only non-content diagnostics |
| Qwen changes a protected term | Repair the exact matched canonical term before insertion |
| User deletes a term during transcription | Use an immutable vocabulary snapshot for that request; deletion applies to the next request |

## 13. Acceptance criteria

### 13.1 Core journey

- Dictating `Space Hotel` can produce `space hotel` on the first run.
- Editing only that phrase to `Spazzz Hotel` produces one unobtrusive suggestion.
- The suggestion does not activate Hush or remove focus from the destination.
- Choosing `Remember` persists `space hotel` to `Spazzz Hotel` locally.
- The entry is active immediately.
- The next raw transcript containing `space hotel` inserts `Spazzz Hotel` exactly.
- The same correction survives an active persona and Edit with AI.

### 13.2 False-positive protection

- Punctuation-only, whitespace-only, casing-only, filler-removal, and broad rewrite edits never produce a suggestion.
- Secure fields never produce a suggestion.
- `space hotels` and `myspace hotel` are not rewritten by the `space hotel` alias.
- Dismissing a suggestion prevents immediate repetition.
- Deleting an entry disables it immediately.

### 13.3 Privacy

- Automated tests prove that only the inserted range is queried.
- No message content, vocabulary term, or alias appears in logs.
- No network request occurs while learning, saving, hinting, or correcting a term.
- Denying Accessibility leaves ordinary transcription functional.

### 13.4 Accessibility and UI

- Suggestion actions are keyboard and VoiceOver accessible.
- The popup is legible in light, dark, increased-contrast, and reduced-motion settings.
- The destination remains first responder throughout the suggestion.
- Text does not clip at the smallest supported HUD size.

## 14. Test strategy

### 14.1 End-to-end first

Following the project bug-fix and journey standard, build the end-user reproduction before implementation:

1. Launch a representative native text destination.
2. Dictate a fixture that transcribes `space hotel`.
3. Verify Hush inserts it.
4. Edit the destination text to `Spazzz Hotel` using the destination app's normal editing path.
5. Verify the non-activating suggestion appears.
6. Confirm `Remember` without losing destination focus.
7. Dictate a second fixture.
8. Verify `Spazzz Hotel` is inserted.
9. Repeat with a persona active.
10. Repeat with Accessibility denied and verify safe degradation.

The E2E fixture should use deterministic audio and a controlled destination app so a recognition-model update cannot make the test flaky.

### 14.2 Domain tests

- Tokenization and minimal substitution extraction.
- Unicode normalization and locale-aware case folding.
- Candidate hard gates and score boundaries.
- Sensitive-pattern exclusion.
- Cooldown behavior.
- Exact phrase matching and punctuation preservation.
- Longest-match overlap resolution.
- Alias uniqueness and loop detection.
- Protected-term validation.

### 14.3 Integration tests

- WhisperKit receives cached prompt tokens for relevant entries.
- Prompt-token failure does not block transcription.
- Raw transcript correction runs before refinement.
- Qwen receives matched canonical forms in the existing request.
- SwiftData changes invalidate the vocabulary snapshot and prompt cache.
- Accessibility observation cannot query outside the inserted range.

### 14.4 Performance tests

- 10, 100, 1,000, and 5,000 entries.
- Short and 500-word transcripts.
- M1 baseline and current Apple silicon.
- Cold and warm WhisperKit state.
- Persona off and on.
- p50, p95, peak memory, and energy impact.

## 15. Implementation seams

Keep components small and independently testable:

```text
PersonalVocabulary/
  Domain/
    VocabularyEntry.swift
    VocabularyHint.swift
    VocabularyReplacement.swift
  Learning/
    InsertionObservation.swift
    CorrectionDiff.swift
    CorrectionCandidateDetector.swift
    SuggestionCooldown.swift
  Runtime/
    VocabularyIndex.swift
    DeterministicAliasCorrector.swift
    WhisperKitVocabularyAdapter.swift
    ProtectedTermValidator.swift
  Persistence/
    VocabularyStore.swift
  UI/
    VocabularySuggestionController.swift
    PersonalVocabularySettingsView.swift
```

Rules:

- Domain types do not import AppKit, WhisperKit, or SwiftData.
- Accessibility observation does not own UI.
- The matcher does not know which transcription provider produced the text.
- The provider adapter does not own persistence.
- The popup receives a view model and emits user intent.
- Every asynchronous boundary is cancellable.

## 16. Future provider adapters

The vocabulary remains reusable if Hush later adopts another speech backend:

| Provider | Adaptation path |
|---|---|
| WhisperKit OSS | Prompt tokens plus deterministic correction |
| Apple Speech | `contextualStrings` or a custom language model plus deterministic correction |
| WhisperKit Pro | Audio-based custom vocabulary plus deterministic validation after compatibility is proven |
| FluidAudio / Parakeet | Parallel CTC custom vocabulary plus deterministic validation after benchmarking |
| No speech hint support | Deterministic correction only |

Apple Speech supports up to 100 short contextual strings and also supports custom language models with pronunciations. Those are useful provider capabilities, but they do not justify replacing the current WhisperKit path in this release.

## 17. Research basis

- [WhisperKit `DecodingOptions`](https://github.com/argmaxinc/argmax-oss-swift/blob/main/Sources/WhisperKit/Core/Configurations.swift)
- [Argmax custom vocabulary](https://app.argmaxinc.com/docs/examples/custom-vocabulary)
- [Argmax open-source and Pro comparison](https://app.argmaxinc.com/docs/wiki/open-source-vs-pro-sdk)
- [Apple Speech contextual strings](https://developer.apple.com/documentation/speech/analysiscontext/contextualstrings)
- [Apple Natural Language](https://developer.apple.com/documentation/naturallanguage)
- [Apple `NLTokenizer`](https://developer.apple.com/documentation/naturallanguage/nltokenizer)
- [Apple `NSSpellChecker`](https://developer.apple.com/documentation/appkit/nsspellchecker)

## 18. Release decision

Ship only when PV-01 is reliable in the real destination-app E2E journey and the false replacement suite passes.

The quality order is:

1. Never change an unrelated word.
2. Always apply a confirmed exact alias.
3. Suggest only corrections that are likely reusable terms.
4. Improve recognition with provider hints where available.
5. Add smarter ranking only after real outcome data exists.

## 19. Final product promise

> Correct it once. Hush remembers how your world is written, privately on your Mac.
