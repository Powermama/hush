# Dictation clean-up journey

This document defines the user-visible contract for the clean-up hush applies in code to every dictation, with or without AI, before the text is inserted.

## Product intent

Hesitation sounds ("uh", "ähm", "euh") never reach the user's document, and nothing the user meant to say is ever removed. The clean-up is instant, needs no model and no download, and works the same with Parakeet and Whisper.

## Invariants

- Two tiers of sounds, kept as data in `Hush/PostProcessing/FillerWords.json` with their sources:
  - Sounds that are a word in no language ("uh", "uhm", "hmm", "хм") are always removed.
  - Sounds that are a real word somewhere ("um" is German for "at", Portuguese for "a") are removed only when the dictation's language is known: from the **Spoken language** setting, or for **Automatic** when language detection is at least 80% sure.
- Drawn-out sounds ("ummm", "hmmmm") count as the sound they stretch. Words that only look like one stay: the verb "err", the unit "mm", "uh-oh", acronyms such as "UM".
- A comma, ellipsis or space that only set the sound off is removed with it ("we should, uh, move" becomes "we should move"). A sentence that started with the sound starts with a capital letter.
- What a word list cannot decide (discourse fillers such as "like" or German "also", self-corrections) is left unchanged.

## Journeys

### CLEAN-001 - Hesitations disappear

Given any dictation in any engine, when the transcript contains a universal hesitation sound, then the inserted text does not contain it and reads as a normal sentence.

### CLEAN-002 - Real words stay

Given the spoken language is German or Portuguese, when the user says "um" as a word ("um 10 Uhr", "um carro"), then it is inserted unchanged.

### CLEAN-003 - Automatic language

Given **Spoken language** is **Automatic**, when detection is sure of the language, then that language's list applies; when it is not sure (very short dictations), only universal sounds are removed.

## Benchmark

`FillerWordsBenchmark` runs the corpus in `HushTests/Fixtures/Cleanup/filler-words.json` and prints exact matches per language, real words removed, sounds left and the median and 95th-percentile time per dictation. Every case without `knownGap` must pass, no real word may be removed, and a known gap that starts passing fails the run until it is promoted to a required case. Expected texts are never edited to make a run pass.

## Test ownership

| Journey | Automated coverage |
| --- | --- |
| CLEAN-001 | `FillerWordsTests.punctuation`, `FillerWordsTests.stretched`, `FillerWordsTests.basicPostProcessor`, `FillerWordsBenchmark` |
| CLEAN-002 | `FillerWordsTests.gatedTier`, `FillerWordsBenchmark` (de-um-time, pt-um-article) |
| CLEAN-003 | `FillerWordsTests.languageWithoutList`, `FillerWordsBenchmark` (auto cases) |
