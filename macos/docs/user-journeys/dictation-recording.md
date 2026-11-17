# Dictation recording journey

This document defines the user-visible contract for recording a dictation. See PRD R1: no dictation is ever lost.

## Invariants

- One dictation records for at most 2 minutes, so a stuck key or a lost key release cannot record forever.
- Reaching the limit never throws audio away. hush stops listening, transcribes everything said until then and inserts it, exactly as if the key had been released.
- A key release that arrives after the limit does nothing more.
- While recording, the audio is written to `~/Library/Application Support/Hush/Recordings/` as it arrives. It stays there only until the text is inserted, handed to the editor or Assistant, or found to hold no speech; a failed transcription keeps it. At most ten recordings are kept.

## Journeys

### DR-001 - Talk past the recording limit

Given the user holds the hotkey and keeps talking for more than 2 minutes, when the limit is reached, then the HUD goes from Listening to Processing without waiting for the release. The text of the first 2 minutes is inserted, and the HUD shows the neutral notice "Stopped at 2 minutes. Everything until then was kept." When the text could not be inserted and was only copied, the same sentence appears in the error style, so the user notices Before this contract the recording was discarded and the HUD asked the user to hold the hotkey while speaking.

### DR-002 - Get back a dictation interrupted by a crash or sleep

Given hush stopped while a dictation was recorded or transcribed (a crash, a force quit, a sleep), when hush starts again and its speech model is ready, then the recording is transcribed and kept in History as "Recovered", and the HUD says "Recovered an interrupted dictation. It is in History." With History off, the text is copied to the clipboard instead. Recovered text is never inserted, because the app it was meant for is unknown.

## Test ownership

| Journey | Coverage |
| --- | --- |
| DR-001 | `RecordingLimitTests` (audio kept at the cap, later audio dropped, one report), manual journey with `-hush.debug.recording.maxSeconds 5` in a debug build |
| DR-002 | `RecordingJournalTests` (round trip, crash-cut file, active recording excluded, discard, limit, test isolation); manual journey: a partial recording in `Recordings/` appears in History as Recovered after launch |
