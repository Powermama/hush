# Typing benchmark journey

This document defines the user-visible contract for measuring a local typing pace from the Time Saved view.

## Journey

1. The user opens Time Saved from Dashboard and starts the typing benchmark.
2. Hush opens a focused 30-second sheet and places keyboard focus in the passage automatically.
3. Before the first keystroke, the active word is shown as the immediate target and highlighted inside the passage. The timer does not start early.
4. While the user types, the full active word remains quietly highlighted for context. The exact next character receives the stronger marker, including a visible marker when Space is next.
5. Correctness remains character-based: correct characters, incorrect characters, and spacing are tracked independently. Mistakes remain visibly marked without turning the whole word into an error state.
6. Time remaining is the primary live metric. WPM and accuracy stay visible as supporting feedback without competing with the passage.
7. After 30 seconds or completion of the passage, Hush stores the result locally and updates the personalized time-saved estimate.
8. The user can close the sheet or run another fresh passage.

The passage is the dominant surface. It uses a comfortable macOS reading size, generous line spacing, and enough horizontal room to maintain the user's place. Hush does not add game modes, leaderboards, sound effects, or decorative controls to this calibration task.

Optional everyday typing measurement uses a listen-only event tap and stores only daily counts and active seconds. Turning measurement off, losing Accessibility permission, or quitting must stop monitoring without repeatedly saving an unchanged aggregate. Changes after shutdown must not restart the monitor.

## Acceptance mapping

| ID | Contract | Verification |
|---|---|---|
| TYPE-001 | The sheet opens from Time Saved with keyboard focus ready and the timer still at 30 seconds. | `TypingBenchmarkJourneyTests.testTypingBenchmarkKeepsThePassageAsThePrimaryTask` |
| TYPE-002 | The current word is exposed as the immediate target and highlighted as a complete word in the passage. | UI journey, accessibility identifier `hush.typing.current-word`, and screenshot inspection |
| TYPE-003 | Typing advances the active word while preserving exact-character, space, and mistake feedback. | `TypingBenchmarkJourneyTests.testTypingBenchmarkKeepsThePassageAsThePrimaryTask` and screenshot inspection |
| TYPE-004 | Time remaining has stronger hierarchy than WPM and accuracy, while the passage remains the primary task. | Screenshot inspection in ready and in-progress states |
| TYPE-005 | The passage has a wider reading surface and remains legible in the supported macOS appearances. | UI journey screenshots and Release build |
| TYPE-006 | Results remain local and update the same personalized typing baseline used by Time Saved. | Existing settings persistence path and Release build |
| TYPE-007 | Permission loss and disabling everyday measurement settle without a settings notification loop. Shutdown removes observers; unchanged totals do not publish. | `TypingActivityMonitorTests.permissionLossSettles` (both paths) and `onlyChangedAggregatesPublish` |
