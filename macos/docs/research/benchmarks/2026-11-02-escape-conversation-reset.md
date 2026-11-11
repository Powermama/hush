# Escape ends the conversation

## Contract

Keyboard Escape, the cursor's Esc button, Dismiss Hush, and explicit New conversation clear in-memory conversation turns, pending proposals, captured context, previous edit bindings, and sequence checkpoints. The next voice invocation starts fresh. Without an explicit reset, ordinary voice follow-ups retain their context, including after the cursor fades. The existing 15-minute inactivity expiry remains in place.

Reset does not delete text in another app or the explicitly enabled, development-only diagnostic files. No new persistent storage or production logging was added.

## Failure and implementation

The reported Notes failure arose when the previous verified edit survived while the native editor was reused for another note. `stop()` previously cancelled work but retained history and `lastEdit`. A write in the same editor could therefore be coerced into a revision against the old text.

Reset now clears that state immediately. A conversation UUID prevents an already-dispatched edit's late verification result from restoring the old binding or history. Native verification still finishes once, without repeating the mutation or claiming it was undone. A late verification error cannot restart speech after cancellation. Recording waits until any in-flight verification finishes.

An idle fade retains the Escape monitors while conversation history exists. Outside input that cancels an action preserves conversation history; it does not implicitly act as Escape. Fresh context and changed-destination checks before every mutation remain intact. This change defines the explicit session boundary; it does not relax stale-range validation within an ongoing conversation.

## Verification on the development Mac

| Check | Result |
| --- | --- |
| Before-fix controller suite | 15 passed, 2 failed: `escapeStartsFresh` and `cancelAfterDispatch` reproduced retained history and old edit state |
| After-fix controller and sequence suites | 32 passed |
| Native UI journeys | 7 passed |
| Provenance package tests | 27 passed |
| Swift-to-Hono integration | 1 passed against the local test-only service; server then stopped |
| Optimized Debug and full Release builds | Passed |
| Release development-recorder exclusion | Passed with Debug positive control |
| Installed binary and signing | Installed Debug executable matches the tested build; strict code-signature verification passed |

The seven UI checks cover keyboard Escape after the cursor fades, clicking the Esc button, an unchanged-session spoken revision, a revision misclassified as write, cancellation before a late reply, inactive-app Esc dismissal, and Escape during a checked sequence. The reused-editor fixture writes a first draft, opens a new empty note in the same native text view, ends the conversation, and verifies a fresh insertion.

The first UI attempt could not establish foreground focus and was not counted as a reproduction. The debug working-app fixture now activates as a regular app. Reset tests require foreground ownership and a verified initial draft before proceeding. The later run passed all 39 selected checks with no skips. Fixture speech/model responses are simulated; these tests do not measure Parakeet, Qwen, Kokoro, or live Notes accuracy.

Installed executable SHA-256: `0f418ce63c3fa768ec7db650650eae8acaa3e7598b3234c004c7cc720366ab25`.

The installed-app permission probe reported `accessibility: false` after replacement, consistent with the development signing limitation. The updated app was reopened with local diagnostics, but live cross-app use needs Accessibility re-enabled. Temporary test recordings and large result bundles are removed after recording their outcomes.
