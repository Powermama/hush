# Empty Notes editor refusal

## User-observed reproduction

The opt-in development trace `418D3C23-21AF-4CE5-B90E-F760B7CF03CC`, started 2026-11-02 at 10:29:21 UTC, records a request to insert a German-breakfast shopping list into the open note. Parakeet transcribed that instruction. Qwen returned `answer` and said it could not edit notes directly. A following acknowledgement (`978B1A1C-7C3A-4E39-9E90-0C426080E6D6`) retained two conversation turns but repeated the refusal.

Both Accessibility and Screen Recording were granted. The focused control was an `AXTextArea` with a settable UTF-16 selection `0:0`. The value was absent. `CoworkerNativeTextAccess.text()` required a non-nil string from `AXValue`, so binding failed with `unsupportedEditor`. Context reported `editable: false`; available actions omitted both `write` and `revise`. The model therefore could not choose insertion under the constrained action schema. No insertion was dispatched.

This is a native capability-detection failure, not missing voice recognition, lost history, or a permission failure in that turn. The model's broad statement about Notes was misleading: the concrete limitation was this field's failed binding. The original trace did not record `AXNumberOfCharacters`, so its value cannot be inferred from these logs.

## Change

The native text transport now distinguishes an omitted value from an unreadable value. When `AXValue` returns success with nil or `noValue`, an independently readable, numeric zero from `AXNumberOfCharacters` permits an empty document. A missing count, nonzero count, unexpected value type, or AX error still rejects the editor. Existing readable strings use the original path without an additional AX query. Selection validation, destination revalidation, one-dispatch paste, and exact text read-back remain shared.

This follows Apple's [editable text character-count attribute](https://developer.apple.com/documentation/applicationservices/kaxnumberofcharactersattribute). It adds no Notes-specific runtime behavior and does not assume unreadable content is empty. Development binding diagnostics now include the AX value status and reported character count, without adding production logging.

## Validation

- 29 focused `CoworkerTests` and `CoworkerSequenceTests` passed, including the new empty-versus-unreadable editor regression. The regression covers nil value with zero length, missing/nonzero/negative/fractional/boolean/string counts, failed AX reads, non-string values, invalid selection, and preservation of existing Unicode text.
- All 27 provenance package tests passed.
- The required Swift-to-Hono integration test passed against the local test-only service.
- Optimized Debug and Release builds passed.
- The updated Debug app was installed in `/Applications/hush.app`.
- The initial installed-app read-only probe returned `accessibility: false`. macOS invalidated the development app's previous grant after replacement. This probe is blocked, not a live Notes pass. The user has been asked to re-enable Accessibility before live insertion qualification.

Debug-only probes: `--inspect-notes-editor` reads the current Notes binding. `--test-notes-editor` uses the observed New Note control, requires an empty editor, inserts a fixed test list, revises it, and checks exact text and no duplication. The test note remains visible; the report is `/private/tmp/hush-notes-editor-check.json`. No model, microphone, or TTS accuracy claim follows from this native transport test.
