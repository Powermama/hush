# Dictation recording journey

This document defines the user-visible contract for recording a dictation. See PRD R1: no dictation is ever lost.

## Invariants

- One dictation records for at most 2 minutes, so a stuck key or a lost key release cannot record forever.
- Reaching the limit never throws audio away. hush stops listening, transcribes everything said until then and inserts it, exactly as if the key had been released.
- A key release that arrives after the limit does nothing more.

## Journeys

### DR-001 - Talk past the recording limit

Given the user holds the hotkey and keeps talking for more than 2 minutes, when the limit is reached, then the HUD goes from Listening to Processing without waiting for the release. The text of the first 2 minutes is inserted, and the HUD says "Stopped at 2 minutes. Everything until then was kept." Before this contract the recording was discarded and the HUD asked the user to hold the hotkey while speaking.

## Test ownership

| Journey | Coverage |
| --- | --- |
| DR-001 | `RecordingLimitTests` (audio kept at the cap, later audio dropped, one report), manual journey with `-hush.debug.recording.maxSeconds 5` in a debug build |
