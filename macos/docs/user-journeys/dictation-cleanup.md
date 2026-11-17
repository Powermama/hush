# Dictation clean-up journey

This document defines the user-visible contract for the clean-up hush applies in code to every dictation, with or without AI, before the text is inserted.

## Product intent

Sounds that are never words ("uh", "ähm", "euh") never reach the user's document, and nothing the user meant to say is ever removed. This is a safety floor: instant, no model, no download, the same for Parakeet and Whisper and for every language. Everything that depends on the language ("um" is German for "at", "like", German "also", self-corrections) is left to the speech model and to hush AI, which see the whole sentence.

## Invariants

- One list of sounds that are a word in no language, kept as data in `Hush/PostProcessing/FillerWords.json` with its sources. A sound that is a real word in any language is never added.
- Drawn-out sounds ("ummm", "hmmmm") count as the sound they stretch. Words that only look like one stay: the verb "err", the unit "mm", "uh-oh", acronyms.
- A comma, ellipsis or space that only set the sound off is removed with it ("sollten, äh, morgen" becomes "sollten morgen"). A sentence that started with the sound starts with a capital letter.
- The clean-up is recorded as the local cleanup step in a Verified Messages chronology, like every other local clean-up.

## Journeys

### CLEAN-001 - Sounds disappear

Given any dictation in any engine and language, when the transcript contains a sound from the list, then the inserted text does not contain it and reads as a normal sentence.

### CLEAN-002 - Real words stay

Given any language, when the user says a word that sounds like a filler ("um 10 Uhr", "um carro", "Er hat angerufen"), then it is inserted unchanged.

## Benchmark

`FillerWordsBenchmark` runs the corpus in `HushTests/Fixtures/Cleanup/filler-words.json` and prints exact matches per language, real words removed, sounds left and the median and 95th-percentile time per dictation. Every case without `knownGap` must pass, no real word may be removed, and a known gap that starts passing fails the run until it is promoted to a required case. Expected texts are never edited to make a run pass. Known gaps record what belongs to the models: English "um" and "er", discourse fillers, self-corrections.

`SpeechFillerBenchmark` (opt-in) measures the step before: which fillers each speech engine already drops, per language.

## Test ownership

| Journey | Automated coverage |
| --- | --- |
| CLEAN-001 | `FillerWordsTests.languageIndependent`, `FillerWordsTests.punctuation`, `FillerWordsTests.stretched`, `FillerWordsTests.basicPostProcessor`, `FillerWordsBenchmark` |
| CLEAN-002 | `FillerWordsTests.bundledList`, `FillerWordsTests.languageIndependent`, `FillerWordsBenchmark` (de-um-time, pt-um-article, de-er-pronoun, en-err-verb) |
